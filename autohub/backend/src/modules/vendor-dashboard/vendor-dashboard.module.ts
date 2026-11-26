import { Controller, Get, Module } from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiTags } from '@nestjs/swagger';
import { sql } from 'kysely';
import { AllowUnapprovedVendor, CurrentVendor, VendorContext, VendorRole } from '../../common/auth';
import { istDate, istMidnight, istTime } from '../../common/http';
import { Database, InjectDb } from '../../infra/db/database';

@ApiTags('vendor')
@ApiBearerAuth()
@ApiHeader({ name: 'X-Vendor-Id', required: true })
@Controller('vendor')
export class VendorDashboardController {
  constructor(@InjectDb() private readonly db: Database) {}

  /** Everything the vendor home screen needs, in one round trip. */
  @Get('dashboard') @VendorRole('staff') @AllowUnapprovedVendor()
  async dashboard(@CurrentVendor() vendor: VendorContext) {
    const vid = vendor.id;
    const today = istDate();
    const dayStart = istMidnight(today);
    const dayEnd = new Date(dayStart.getTime() + 86400_000);
    const weekStart = new Date(dayStart.getTime() - 6 * 86400_000);
    const showMoney = vendor.role !== 'staff';

    const [profile, bookingCounts, orderCounts, revenueToday, actionBookings, actionOrders, lowStock, ledger, payout, series, unread, upcoming] =
      await Promise.all([
        this.db.selectFrom('vendors').select(['id', 'businessName', 'status', 'statusReason', 'isAcceptingOrders', 'ratingAvg', 'ratingCount', 'businessDomains'])
          .where('id', '=', vid).executeTakeFirstOrThrow(),
        this.db.selectFrom('bookings').select(['status', (eb) => eb.fn.countAll<number>().as('n')])
          .where('vendorId', '=', vid).where('scheduledStart', '>=', dayStart).where('scheduledStart', '<', dayEnd).groupBy('status').execute(),
        this.db.selectFrom('orders').select(['status', (eb) => eb.fn.countAll<number>().as('n')])
          .where('vendorId', '=', vid).where('status', 'in', ['placed', 'accepted', 'packed']).groupBy('status').execute(),
        sql<{ paise: number }>`
          SELECT coalesce((SELECT sum(final_total_paise) FROM bookings WHERE vendor_id = ${vid} AND status = 'completed'
                             AND completed_at >= ${dayStart} AND completed_at < ${dayEnd}), 0)
               + coalesce((SELECT sum(total_paise) FROM orders WHERE vendor_id = ${vid} AND status = 'delivered'
                             AND delivered_at >= ${dayStart} AND delivered_at < ${dayEnd}), 0) AS paise`.execute(this.db),
        this.db.selectFrom('bookings as b').innerJoin('vehicles as ve', 've.id', 'b.vehicleId').innerJoin('vehicleModels as m', 'm.id', 've.modelId')
          .select(['b.id', 'b.bookingNumber', 'b.status', 'b.scheduledStart', 'm.name as model'])
          .where('b.vendorId', '=', vid).where('b.status', 'in', ['requested', 'ready'])
          .orderBy('b.scheduledStart').limit(10).execute(),
        this.db.selectFrom('orders').select(['id', 'orderNumber', 'createdAt', 'totalPaise'])
          .where('vendorId', '=', vid).where('status', '=', 'placed').orderBy('createdAt').limit(10).execute(),
        this.db.selectFrom('products').select(['id', 'name', sql<number>`stock_qty - reserved_qty`.as('available')])
          .where('vendorId', '=', vid).where('status', '=', 'active').where('deletedAt', 'is', null)
          .where(sql<boolean>`stock_qty - reserved_qty <= low_stock_threshold`).orderBy(sql`stock_qty - reserved_qty`).limit(5).execute(),
        sql<{ available: number; onHold: number }>`
          SELECT coalesce(sum(amount_paise) FILTER (WHERE available_at <= now()), 0) AS available,
                 coalesce(sum(amount_paise) FILTER (WHERE available_at > now()), 0)  AS on_hold
          FROM vendor_ledger_entries WHERE vendor_id = ${vid}`.execute(this.db),
        this.db.selectFrom('payouts').select(['id', 'amountPaise', 'status', 'requestedAt'])
          .where('vendorId', '=', vid).where('status', 'in', ['requested', 'approved', 'processing']).executeTakeFirst(),
        sql<{ date: string; revenuePaise: number; orders: number; bookings: number; profileViews: number }>`
          WITH days AS (SELECT generate_series(${istDate(weekStart)}::date, ${today}::date, interval '1 day')::date AS d)
          SELECT to_char(d, 'YYYY-MM-DD') AS date,
            coalesce((SELECT sum(final_total_paise) FROM bookings WHERE vendor_id = ${vid} AND status = 'completed'
                        AND (completed_at AT TIME ZONE 'Asia/Kolkata')::date = d), 0)
          + coalesce((SELECT sum(total_paise) FROM orders WHERE vendor_id = ${vid} AND status = 'delivered'
                        AND (delivered_at AT TIME ZONE 'Asia/Kolkata')::date = d), 0) AS revenue_paise,
            (SELECT count(*)::int FROM orders WHERE vendor_id = ${vid} AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = d
               AND status NOT IN ('pending_payment', 'payment_failed')) AS orders,
            (SELECT count(*)::int FROM bookings WHERE vendor_id = ${vid} AND (scheduled_start AT TIME ZONE 'Asia/Kolkata')::date = d
               AND status NOT IN ('cancelled', 'rejected')) AS bookings,
            coalesce((SELECT profile_views FROM vendor_daily_stats WHERE vendor_id = ${vid} AND day = d), 0) AS profile_views
          FROM days ORDER BY d`.execute(this.db),
        sql<{ n: number }>`
          SELECT count(*)::int AS n FROM chat_conversations c
          WHERE c.vendor_id = ${vid} AND EXISTS (
            SELECT 1 FROM chat_messages m WHERE m.conversation_id = c.id AND m.id > c.vendor_last_read_id AND m.sender_role = 'customer')`.execute(this.db),
        this.db.selectFrom('bookings as b').innerJoin('vehicles as ve', 've.id', 'b.vehicleId')
          .innerJoin('vehicleModels as m', 'm.id', 've.modelId').innerJoin('users as u', 'u.id', 'b.customerId')
          .select(['b.id', 'b.bookingNumber', 'b.status', 'b.scheduledStart', 'm.name as model', 've.registrationNumber', 'u.fullName as customerName',
            (eb) => eb.selectFrom('bookingServices as bs').select(sql<string>`string_agg(bs.name_snapshot, ', ')`.as('x'))
              .whereRef('bs.bookingId', '=', 'b.id').as('serviceNames')])
          .where('b.vendorId', '=', vid).where('b.scheduledStart', '>=', dayStart).where('b.scheduledStart', '<', dayEnd)
          .where('b.status', 'not in', ['cancelled', 'rejected', 'no_show']).orderBy('b.scheduledStart').execute(),
      ]);

    const count = (rows: { status: string; n: number }[], ...s: string[]) => rows.filter((r) => s.includes(r.status)).reduce((a, r) => a + Number(r.n), 0);
    const actionItems = [
      ...actionOrders.map((o) => ({ type: 'order_pending_acceptance', id: o.id, label: `${o.orderNumber}`, at: o.createdAt })),
      ...actionBookings.map((b) => ({
        type: b.status === 'requested' ? 'booking_pending_confirmation' : 'booking_awaiting_payment',
        id: b.id, label: `${b.bookingNumber} · ${b.model} · ${istTime(b.scheduledStart)}`, at: b.scheduledStart,
      })),
      ...lowStock.map((p) => ({ type: 'low_stock', id: p.id, label: `${p.name} · ${p.available} left`, at: null })),
    ];

    return {
      vendor: { ...profile, ratingAvg: Number(profile.ratingAvg) },
      today: {
        date: today,
        newOrders: count(orderCounts, 'placed'),
        ordersToDispatch: count(orderCounts, 'accepted', 'packed'),
        bookings: {
          total: bookingCounts.filter((r) => !['cancelled', 'rejected', 'no_show'].includes(r.status)).reduce((a, r) => a + Number(r.n), 0),
          requested: count(bookingCounts, 'requested'),
          inProgress: count(bookingCounts, 'confirmed', 'vehicle_received', 'estimate_shared', 'in_progress', 'ready'),
          completed: count(bookingCounts, 'completed'),
        },
        revenuePaise: showMoney ? Number(revenueToday.rows[0].paise) : null,
        schedule: upcoming.map((b) => ({ ...b, localTime: istTime(b.scheduledStart) })),
      },
      actionItems,
      earnings: showMoney ? {
        availablePaise: Number(ledger.rows[0].available), onHoldPaise: Number(ledger.rows[0].onHold), payoutInProgress: payout ?? null,
      } : null,
      last7Days: series.rows.map((r) => ({ ...r, revenuePaise: showMoney ? Number(r.revenuePaise) : null })),
      unreadChats: unread.rows[0].n,
    };
  }
}

@Module({ controllers: [VendorDashboardController] })
export class VendorDashboardModule {}
