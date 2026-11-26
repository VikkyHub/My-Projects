import { Inject, Injectable } from '@nestjs/common';
import { sql } from 'kysely';
import { ENV, Env } from '../../config/env';
import { Errors } from '../../common/errors';
import { decodeCursor, istTime, page } from '../../common/http';
import { bpsOf, settle, taxFromInclusive } from '../../common/money';
import { Database, InjectDb, Tx } from '../../infra/db/database';
import type { ActorKind, BookingStatus, LineKind, ServiceLocation } from '../../infra/db/db.types';

export interface CreateBookingInput {
  vendorId: string; vehicleId: string; serviceIds: string[]; slotId: string;
  locationType?: ServiceLocation; addressId?: string; customerNotes?: string; odometerKm?: number;
  payAdvance?: boolean; attachments?: { kind: 'issue_photo'; publicId: string; url: string; caption?: string }[];
}
export interface EstimateItemInput {
  kind: LineKind; description: string; serviceId?: string; productId?: string; hsnSacCode?: string;
  quantity: number; unitPricePaise: number; gstRateBps: number; isOptional?: boolean;
}

const ACTIVE: BookingStatus[] = ['requested', 'confirmed', 'vehicle_received', 'estimate_shared', 'in_progress', 'ready'];
const CANCEL_NOTICE_MS = 2 * 3600_000;

@Injectable()
export class BookingsService {
  constructor(@InjectDb() private readonly db: Database, @Inject(ENV) private readonly env: Env) {}

  // ======================= customer =======================

  async create(customerId: string, input: CreateBookingInput, idempotencyKey: string) {
    const existing = await this.db.selectFrom('bookings').select(['id', 'customerId'])
      .where('idempotencyKey', '=', idempotencyKey).executeTakeFirst();
    if (existing) {
      if (existing.customerId !== customerId) throw Errors.conflict('IDEMPOTENCY_KEY_REUSED', 'Idempotency-Key already used.');
      return { bookingId: existing.id, replayed: true };
    }

    const vendor = await this.db.selectFrom('vendors')
      .select(['id', 'status', 'businessDomains', 'offersDoorstep', 'isAcceptingOrders'])
      .where('id', '=', input.vendorId).where('deletedAt', 'is', null).executeTakeFirst();
    if (!vendor || vendor.status !== 'approved') throw Errors.notFound('Shop');
    if (!vendor.isAcceptingOrders) throw Errors.rule('VENDOR_NOT_ACCEPTING', 'This shop is not taking bookings right now.');

    const vehicle = await this.db.selectFrom('vehicles').select(['id', 'odometerKm'])
      .where('id', '=', input.vehicleId).where('userId', '=', customerId).where('deletedAt', 'is', null).executeTakeFirst();
    if (!vehicle) throw Errors.notFound('Vehicle');

    const serviceIds = [...new Set(input.serviceIds)];
    const services = await this.db.selectFrom('services as s')
      .innerJoin('subcategories as sc', 'sc.id', 's.subcategoryId').innerJoin('categories as c', 'c.id', 'sc.categoryId')
      .select(['s.id', 's.name', 's.priceType', 's.pricePaise', 's.gstRateBps', 's.advancePaise', 's.doorstepAvailable', 'c.domain'])
      .where('s.id', 'in', serviceIds).where('s.vendorId', '=', vendor.id)
      .where('s.status', '=', 'active').where('s.deletedAt', 'is', null).execute();
    if (services.length !== serviceIds.length) throw Errors.validation({ serviceIds: 'one or more services are not available at this shop' });
    const domains = new Set(services.map((s) => s.domain));
    if (domains.size !== 1) throw Errors.validation({ serviceIds: 'book service and decor work separately' });
    const domain = services[0].domain;
    if (domain === 'parts' || !vendor.businessDomains.includes(domain)) throw Errors.validation({ serviceIds: 'not bookable' });

    const locationType = input.locationType ?? 'at_shop';
    let addressSnapshot: Record<string, unknown> | null = null;
    if (locationType !== 'at_shop') {
      if (!vendor.offersDoorstep || services.some((s) => !s.doorstepAvailable)) {
        throw Errors.validation({ locationType: 'doorstep service is not available for this selection' });
      }
      if (!input.addressId) throw Errors.validation({ addressId: 'required for doorstep / pickup' });
      const a = await this.db.selectFrom('addresses')
        .select(['contactName', 'contactPhone', 'line1', 'line2', 'landmark', 'city', 'state', 'pincode',
          sql<number | null>`ST_Y(location::geometry)`.as('lat'), sql<number | null>`ST_X(location::geometry)`.as('lng')])
        .where('id', '=', input.addressId).where('userId', '=', customerId).where('deletedAt', 'is', null).executeTakeFirst();
      if (!a) throw Errors.notFound('Address');
      addressSnapshot = a;
    }

    const quotedTotalPaise = services.reduce((sum, s) => sum + (s.priceType === 'on_inspection' ? 0 : s.pricePaise ?? 0), 0);
    const advancePaise = input.payAdvance === false ? 0 : services.reduce((sum, s) => sum + s.advancePaise, 0);

    const bookingId = await this.db.transaction().execute(async (tx) => {
      // Atomic seat-taking: succeeds only while booked_count < capacity (also enforced by a CHECK).
      const slot = await tx.updateTable('vendorSlots').set((eb) => ({ bookedCount: eb('bookedCount', '+', 1) }))
        .where('id', '=', input.slotId).where('vendorId', '=', vendor.id).where('isBlocked', '=', false)
        .where('startsAt', '>', new Date(Date.now() + 30 * 60_000))
        .whereRef('bookedCount', '<', 'capacity')
        .returning(['startsAt']).executeTakeFirst();
      if (!slot) {
        const nextSlots = await tx.selectFrom('vendorSlots').select(['id', 'startsAt'])
          .where('vendorId', '=', vendor.id).where('isBlocked', '=', false).where('startsAt', '>', new Date(Date.now() + 30 * 60_000))
          .whereRef('bookedCount', '<', 'capacity').orderBy('startsAt').limit(3).execute();
        throw Errors.conflict('SLOT_UNAVAILABLE', 'That slot was just taken. Pick another time.', { nextSlots });
      }

      const b = await tx.insertInto('bookings').values({
        customerId, vendorId: vendor.id, vehicleId: vehicle.id, domain, slotId: input.slotId,
        scheduledStart: slot.startsAt, locationType, addressId: input.addressId ?? null,
        addressSnapshot: addressSnapshot ? JSON.stringify(addressSnapshot) : null,
        customerNotes: input.customerNotes ?? null, odometerKm: input.odometerKm ?? vehicle.odometerKm,
        quotedTotalPaise, advancePaise, idempotencyKey,
      }).returning('id').executeTakeFirstOrThrow();

      await tx.insertInto('bookingServices').values(services.map((s) => ({
        bookingId: b.id, serviceId: s.id, nameSnapshot: s.name, priceType: s.priceType, pricePaise: s.pricePaise, gstRateBps: s.gstRateBps,
      }))).execute();
      if (input.attachments?.length) {
        await tx.insertInto('bookingAttachments').values(input.attachments.map((a) => ({
          bookingId: b.id, uploadedBy: customerId, kind: a.kind, url: a.url, publicId: a.publicId, caption: a.caption ?? null,
        }))).execute();
      }
      await this.history(tx, b.id, null, 'requested', 'customer', customerId);
      return b.id;
    });
    return { bookingId, replayed: false };
  }

  async listForCustomer(customerId: string, scope: 'active' | 'past' | undefined, cursor?: string) {
    const offset = decodeCursor(cursor);
    const rows = await this.db.selectFrom('bookings as b').innerJoin('vendors as v', 'v.id', 'b.vendorId')
      .innerJoin('vehicles as ve', 've.id', 'b.vehicleId').innerJoin('vehicleModels as m', 'm.id', 've.modelId')
      .select(['b.id', 'b.bookingNumber', 'b.status', 'b.domain', 'b.scheduledStart', 'b.quotedTotalPaise', 'b.finalTotalPaise',
        'b.paymentState', 'v.businessName as vendorName', 'm.name as vehicleModel', 've.registrationNumber'])
      .where('b.customerId', '=', customerId)
      .$if(scope === 'active', (q) => q.where('b.status', 'in', ACTIVE))
      .$if(scope === 'past', (q) => q.where('b.status', 'not in', ACTIVE))
      .orderBy('b.scheduledStart', 'desc').limit(21).offset(offset).execute();
    return page(rows, offset, 20);
  }

  async cancelByCustomer(customerId: string, bookingId: string, reason?: string) {
    await this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { customerId });
      if (!['requested', 'confirmed'].includes(b.status)) throw Errors.invalidTransition(b.status, 'cancel', ['requested', 'confirmed']);
      if (b.status === 'confirmed' && b.scheduledStart.getTime() - Date.now() < CANCEL_NOTICE_MS) {
        throw Errors.rule('CANCELLATION_WINDOW_CLOSED', 'Bookings can be cancelled up to 2 hours before the slot. Please call the shop.');
      }
      await this.closeWithRelease(tx, b, 'cancelled', 'customer', customerId, reason ?? 'Cancelled by customer');
    });
  }

  async approveEstimate(customerId: string, bookingId: string, estimateId: string, declinedItemIds: string[]) {
    await this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { customerId });
      if (b.status !== 'estimate_shared') throw Errors.invalidTransition(b.status, 'approve an estimate', ['estimate_shared']);
      const est = await tx.selectFrom('bookingEstimates').selectAll().where('id', '=', estimateId).where('bookingId', '=', bookingId).executeTakeFirst();
      if (!est || est.status !== 'pending') throw Errors.conflict('CONFLICT', 'This estimate is no longer open.');
      if (est.validUntil && est.validUntil.getTime() < Date.now()) throw Errors.rule('ESTIMATE_EXPIRED', 'This estimate has expired. Ask the shop to resend it.');

      const items = await tx.selectFrom('bookingEstimateItems').selectAll().where('estimateId', '=', estimateId).execute();
      const declined = new Set(declinedItemIds);
      for (const id of declined) {
        const item = items.find((i) => i.id === id);
        if (!item) throw Errors.validation({ declinedItemIds: `unknown item ${id}` });
        if (!item.isOptional) throw Errors.validation({ declinedItemIds: `"${item.description}" is required and cannot be declined` });
      }
      if (declined.size) {
        await tx.updateTable('bookingEstimateItems').set({ isAccepted: false }).where('id', 'in', [...declined]).execute();
      }
      const totals = estimateTotals(items.filter((i) => !declined.has(i.id)));
      await tx.updateTable('bookingEstimates').set({ status: 'approved', respondedAt: new Date(), ...totals }).where('id', '=', estimateId).execute();
      await tx.updateTable('bookings').set({ status: 'in_progress', startedAt: new Date(), finalTotalPaise: totals.totalPaise })
        .where('id', '=', bookingId).execute();
      await this.history(tx, bookingId, b.status, 'in_progress', 'customer', customerId, 'Estimate approved');
    });
  }

  async rejectEstimate(customerId: string, bookingId: string, estimateId: string, reason?: string) {
    await this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { customerId });
      if (b.status !== 'estimate_shared') throw Errors.invalidTransition(b.status, 'reject an estimate', ['estimate_shared']);
      const r = await tx.updateTable('bookingEstimates').set({ status: 'rejected', respondedAt: new Date() })
        .where('id', '=', estimateId).where('bookingId', '=', bookingId).where('status', '=', 'pending').executeTakeFirst();
      if (!r.numUpdatedRows) throw Errors.conflict('CONFLICT', 'This estimate is no longer open.');
      // Booking stays in estimate_shared: the shop can revise the estimate or close the job.
      await this.history(tx, bookingId, b.status, b.status, 'customer', customerId, `Estimate rejected${reason ? `: ${reason}` : ''}`);
    });
  }

  // ======================= vendor =======================

  async listForVendor(vendorId: string, opts: { date?: string; status?: BookingStatus; cursor?: string }) {
    const offset = decodeCursor(opts.cursor);
    let q = this.db.selectFrom('bookings as b').innerJoin('users as u', 'u.id', 'b.customerId')
      .innerJoin('vehicles as ve', 've.id', 'b.vehicleId').innerJoin('vehicleModels as m', 'm.id', 've.modelId')
      .innerJoin('vehicleMakes as mk', 'mk.id', 've.makeId')
      .select(['b.id', 'b.bookingNumber', 'b.status', 'b.domain', 'b.scheduledStart', 'b.quotedTotalPaise', 'b.finalTotalPaise',
        'b.paymentState', 'b.locationType', 'u.fullName as customerName', 'mk.name as make', 'm.name as model', 've.registrationNumber',
        (eb) => eb.selectFrom('bookingServices as bs').select(sql<string>`string_agg(bs.name_snapshot, ', ')`.as('x'))
          .whereRef('bs.bookingId', '=', 'b.id').as('serviceNames')])
      .where('b.vendorId', '=', vendorId);
    if (opts.date) {
      q = q.where(sql<boolean>`(b.scheduled_start AT TIME ZONE 'Asia/Kolkata')::date = ${opts.date}::date`);
    }
    if (opts.status) q = q.where('b.status', '=', opts.status);
    const rows = await q.orderBy('b.scheduledStart').limit(51).offset(offset).execute();
    const res = page(rows, offset, 50);
    return { ...res, data: res.data.map((r) => ({ ...r, localTime: istTime(r.scheduledStart) })) };
  }

  async vendorTransition(vendorId: string, actorId: string, bookingId: string,
    action: 'confirm' | 'reject' | 'check_in' | 'start' | 'ready' | 'no_show', extra: { reason?: string; odometerKm?: number } = {}) {
    await this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { vendorId });
      const need = (allowed: BookingStatus[]) => {
        if (!allowed.includes(b.status)) throw Errors.invalidTransition(b.status, action.replace('_', ' '), allowed);
      };
      const move = async (to: BookingStatus, set: Record<string, unknown> = {}, note?: string) => {
        await tx.updateTable('bookings').set({ status: to, ...set }).where('id', '=', b.id).execute();
        await this.history(tx, b.id, b.status, to, 'vendor', actorId, note);
      };

      switch (action) {
        case 'confirm':
          need(['requested']);
          return move('confirmed', { confirmedAt: new Date() });
        case 'reject':
          need(['requested']);
          return this.closeWithRelease(tx, b, 'rejected', 'vendor', actorId, extra.reason ?? 'Rejected by shop');
        case 'check_in':
          need(['confirmed']);
          return move('vehicle_received', extra.odometerKm != null ? { odometerKm: extra.odometerKm } : {});
        case 'no_show':
          need(['confirmed']);
          if (Date.now() < b.scheduledStart.getTime() + 30 * 60_000) throw Errors.rule('TOO_EARLY', 'Mark no-show only 30 minutes after the slot starts.');
          return this.closeWithRelease(tx, b, 'no_show', 'vendor', actorId, 'Customer did not arrive', { refund: false });
        case 'start': {
          need(['vehicle_received']);
          const services = await tx.selectFrom('bookingServices').select(['priceType', 'pricePaise']).where('bookingId', '=', b.id).execute();
          if (services.some((s) => s.priceType !== 'fixed')) {
            throw Errors.rule('ESTIMATE_REQUIRED', 'Some services are priced after inspection. Send an estimate first.');
          }
          return move('in_progress', { startedAt: new Date(), finalTotalPaise: services.reduce((s, x) => s + (x.pricePaise ?? 0), 0) });
        }
        case 'ready': {
          need(['in_progress']);
          await move('ready');
          const fresh = await tx.selectFrom('bookings').selectAll().where('id', '=', b.id).executeTakeFirstOrThrow();
          if (fresh.finalTotalPaise != null && fresh.amountPaidPaise >= fresh.finalTotalPaise) {
            await this.complete(tx, fresh.id, 'system', null);   // advance already covered everything
          }
          return;
        }
      }
    });
  }

  async createEstimate(vendorId: string, actorId: string, bookingId: string, items: EstimateItemInput[], vendorNote?: string, validForHours = 24) {
    return this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { vendorId });
      const allowed: BookingStatus[] = ['vehicle_received', 'estimate_shared', 'in_progress'];
      if (!allowed.includes(b.status)) throw Errors.invalidTransition(b.status, 'send an estimate', allowed);
      for (const i of items) {
        if (i.kind === 'discount' ? i.unitPricePaise > 0 : i.unitPricePaise < 0) {
          throw Errors.validation({ items: `"${i.description}": only discount lines can be negative` });
        }
      }
      await tx.updateTable('bookingEstimates').set({ status: 'superseded' }).where('bookingId', '=', bookingId).where('status', '=', 'pending').execute();
      const last = await tx.selectFrom('bookingEstimates').select((eb) => eb.fn.max('version').as('v')).where('bookingId', '=', bookingId).executeTakeFirst();
      const totals = estimateTotals(items.map((i) => ({ ...i, isAccepted: true })));
      if (totals.totalPaise < 0) throw Errors.validation({ items: 'estimate total cannot be negative' });
      const est = await tx.insertInto('bookingEstimates').values({
        bookingId, version: (last?.v ?? 0) + 1, ...totals, vendorNote: vendorNote ?? null,
        validUntil: new Date(Date.now() + validForHours * 3600_000), createdBy: actorId,
      }).returning(['id', 'version', 'status', 'subtotalPaise', 'taxPaise', 'totalPaise', 'validUntil']).executeTakeFirstOrThrow();
      await tx.insertInto('bookingEstimateItems').values(items.map((i, idx) => ({
        estimateId: est.id, kind: i.kind, description: i.description, serviceId: i.serviceId ?? null, productId: i.productId ?? null,
        hsnSacCode: i.hsnSacCode ?? null, quantity: i.quantity, unitPricePaise: i.unitPricePaise, gstRateBps: i.gstRateBps,
        isOptional: i.isOptional ?? false, sortOrder: idx,
      }))).execute();
      if (b.status !== 'estimate_shared') {
        await tx.updateTable('bookings').set({ status: 'estimate_shared' }).where('id', '=', bookingId).execute();
      }
      await this.history(tx, bookingId, b.status, 'estimate_shared', 'vendor', actorId, `Estimate v${est.version} shared`);
      return est;
    });
  }

  /** Cash / direct-UPI collected at the shop for the remaining balance. Completes the job. */
  async recordOfflinePayment(vendorId: string, actorId: string, bookingId: string, amountPaise: number) {
    await this.db.transaction().execute(async (tx) => {
      const b = await this.lock(tx, bookingId, { vendorId });
      if (b.status !== 'ready') throw Errors.invalidTransition(b.status, 'record payment', ['ready']);
      const due = (b.finalTotalPaise ?? 0) - b.amountPaidPaise;
      if (amountPaise !== due) throw Errors.validation({ amountPaise: `balance due is ${due} paise` });
      await tx.updateTable('bookings').set({ amountPaidPaise: b.amountPaidPaise + amountPaise, paymentState: 'paid' }).where('id', '=', b.id).execute();
      await this.complete(tx, b.id, 'vendor', actorId, amountPaise);
    });
  }

  // ======================= payments hook =======================

  /** Called by PaymentsService inside its capture transaction. */
  async applyCapturedPayment(tx: Tx, bookingId: string, amountPaise: number) {
    const b = await tx.selectFrom('bookings').selectAll().where('id', '=', bookingId).forUpdate().executeTakeFirstOrThrow();
    const paid = b.amountPaidPaise + amountPaise;
    const fullyPaid = b.finalTotalPaise != null && paid >= b.finalTotalPaise;
    await tx.updateTable('bookings').set({ amountPaidPaise: paid, paymentState: fullyPaid ? 'paid' : 'partially_paid' }).where('id', '=', b.id).execute();
    if (fullyPaid && b.status === 'ready') await this.complete(tx, b.id, 'system', null);
  }

  // ======================= views =======================

  async view(bookingId: string, who: { customerId?: string; vendorId?: string }) {
    let q = this.db.selectFrom('bookings as b').innerJoin('vendors as v', 'v.id', 'b.vendorId')
      .innerJoin('vehicles as ve', 've.id', 'b.vehicleId').innerJoin('vehicleModels as m', 'm.id', 've.modelId')
      .innerJoin('vehicleMakes as mk', 'mk.id', 've.makeId').innerJoin('users as u', 'u.id', 'b.customerId')
      .selectAll('b')
      .select(['v.businessName', 'v.phone as vendorPhone', sql<number>`ST_Y(v.location::geometry)`.as('vendorLat'),
        sql<number>`ST_X(v.location::geometry)`.as('vendorLng'), 'mk.name as make', 'm.name as model',
        've.manufactureYear', 've.registrationNumber', 'u.fullName as customerName', 'u.phone as customerPhone'])
      .where('b.id', '=', bookingId);
    if (who.customerId) q = q.where('b.customerId', '=', who.customerId);
    if (who.vendorId) q = q.where('b.vendorId', '=', who.vendorId);
    const b = await q.executeTakeFirst();
    if (!b) throw Errors.notFound('Booking');

    const [services, estimates, attachments, timeline, payments] = await Promise.all([
      this.db.selectFrom('bookingServices').select(['serviceId', 'nameSnapshot as name', 'priceType', 'pricePaise']).where('bookingId', '=', b.id).execute(),
      this.db.selectFrom('bookingEstimates').selectAll().where('bookingId', '=', b.id).orderBy('version', 'desc').execute(),
      this.db.selectFrom('bookingAttachments').select(['id', 'kind', 'url', 'caption', 'uploadedBy', 'createdAt']).where('bookingId', '=', b.id).orderBy('createdAt').execute(),
      this.db.selectFrom('bookingStatusHistory').select(['toStatus as status', 'actor', 'note', 'createdAt as at']).where('bookingId', '=', b.id).orderBy('id').execute(),
      this.db.selectFrom('payments').select(['id', 'purpose', 'status', 'amountPaise', 'razorpayOrderId', 'capturedAt'])
        .where('bookingId', '=', b.id).orderBy('createdAt').execute(),
    ]);
    const current = estimates.find((e) => e.status === 'pending') ?? estimates.find((e) => e.status === 'approved') ?? null;
    const estimateItems = current
      ? await this.db.selectFrom('bookingEstimateItems')
          .select(['id', 'kind', 'description', 'quantity', 'unitPricePaise', 'gstRateBps', 'isOptional', 'isAccepted', 'hsnSacCode'])
          .where('estimateId', '=', current.id).orderBy('sortOrder').execute()
      : [];
    let ifOptionalDeclined = null;
    if (current?.status === 'pending' && estimateItems.some((i) => i.isOptional)) {
      ifOptionalDeclined = estimateTotals(estimateItems.filter((i) => !i.isOptional).map((i) => ({ ...i, isAccepted: true })));
    }

    const s = b.status;
    const balanceDuePaise = b.finalTotalPaise == null ? null : Math.max(b.finalTotalPaise - b.amountPaidPaise, 0);
    const advanceDue = b.advancePaise > b.amountPaidPaise && ['requested', 'confirmed'].includes(s);
    const pendingPayment = payments.find((p) => p.status === 'created');
    const isVendorView = !!who.vendorId;
    return {
      id: b.id, bookingNumber: b.bookingNumber, status: s, domain: b.domain,
      scheduledStart: b.scheduledStart, localTime: istTime(b.scheduledStart), locationType: b.locationType,
      address: b.addressSnapshot, customerNotes: b.customerNotes, odometerKm: b.odometerKm,
      vehicle: { id: b.vehicleId, label: `${b.make} ${b.model} ${b.manufactureYear}${b.registrationNumber ? ` · ${b.registrationNumber}` : ''}` },
      vendor: { id: b.vendorId, businessName: b.businessName, phone: b.vendorPhone, location: { lat: b.vendorLat, lng: b.vendorLng } },
      ...(isVendorView ? {
        customer: { name: b.customerName,
          // Phone is shared once the shop has accepted the job.
          phone: s === 'requested' ? b.customerPhone.replace(/(\+\d{4})\d+(\d{2})$/, '$1••••••$2') : b.customerPhone },
      } : {}),
      services,
      estimate: current ? {
        id: current.id, version: current.version, status: current.status, validUntil: current.validUntil,
        items: estimateItems, subtotalPaise: current.subtotalPaise, taxPaise: current.taxPaise, totalPaise: current.totalPaise,
        ifOptionalDeclined, vendorNote: current.vendorNote,
      } : null,
      payments: {
        quotedTotalPaise: b.quotedTotalPaise, finalTotalPaise: b.finalTotalPaise, advancePaise: b.advancePaise,
        amountPaidPaise: b.amountPaidPaise, balanceDuePaise, paymentState: b.paymentState,
        pending: pendingPayment ? { paymentId: pendingPayment.id, purpose: pendingPayment.purpose, amountPaise: pendingPayment.amountPaise } : null,
      },
      ...(isVendorView && s === 'completed' ? {
        settlement: { commissionPaise: b.commissionPaise, commissionGstPaise: b.commissionGstPaise, tcsPaise: b.tcsPaise,
          tdsPaise: b.tdsPaise, vendorPayoutPaise: b.vendorPayoutPaise },
      } : {}),
      attachments: attachments.map((a) => ({ ...a, uploadedBy: a.uploadedBy === b.customerId ? 'customer' : 'vendor' })),
      timeline,
      actions: isVendorView ? {
        canConfirm: s === 'requested', canReject: s === 'requested', canCheckIn: s === 'confirmed',
        canSendEstimate: ['vehicle_received', 'estimate_shared', 'in_progress'].includes(s),
        canStart: s === 'vehicle_received', canMarkReady: s === 'in_progress', canRecordPayment: s === 'ready' && (balanceDuePaise ?? 0) > 0,
      } : {
        canCancel: s === 'requested' || (s === 'confirmed' && b.scheduledStart.getTime() - Date.now() >= CANCEL_NOTICE_MS),
        canApproveEstimate: s === 'estimate_shared' && current?.status === 'pending',
        canPayAdvance: advanceDue, canPayBalance: s === 'ready' && (balanceDuePaise ?? 0) > 0,
        canReview: s === 'completed', canChat: true,
      },
      createdAt: b.createdAt,
    };
  }

  // ======================= internals =======================

  private async lock(tx: Tx, bookingId: string, who: { customerId?: string; vendorId?: string }) {
    let q = tx.selectFrom('bookings').selectAll().where('id', '=', bookingId);
    if (who.customerId) q = q.where('customerId', '=', who.customerId);
    if (who.vendorId) q = q.where('vendorId', '=', who.vendorId);
    const b = await q.forUpdate().executeTakeFirst();
    if (!b) throw Errors.notFound('Booking');
    return b;
  }

  private async history(tx: Tx, bookingId: string, from: BookingStatus | null, to: BookingStatus, actor: ActorKind, actorId: string | null, note?: string) {
    await tx.insertInto('bookingStatusHistory').values({ bookingId, fromStatus: from, toStatus: to, actor, actorId, note: note ?? null }).execute();
  }

  /** Cancel / reject / no-show: free the slot seat and queue a refund of anything paid. */
  private async closeWithRelease(tx: Tx, b: { id: string; status: BookingStatus; slotId: string | null; amountPaidPaise: number },
    to: 'cancelled' | 'rejected' | 'no_show', actor: ActorKind, actorId: string, reason: string, opts = { refund: true }) {
    await tx.updateTable('bookings').set({
      status: to, cancellationReason: reason,
      ...(to === 'cancelled' ? { cancelledAt: new Date(), cancelledBy: actor } : {}),
    }).where('id', '=', b.id).execute();
    if (b.slotId && to !== 'no_show') {
      await tx.updateTable('vendorSlots').set((eb) => ({ bookedCount: eb('bookedCount', '-', 1) }))
        .where('id', '=', b.slotId).where('bookedCount', '>', 0).execute();
    }
    if (opts.refund && b.amountPaidPaise > 0) {
      const payment = await tx.selectFrom('payments').select('id').where('bookingId', '=', b.id).where('status', '=', 'captured')
        .orderBy('capturedAt').limit(1).executeTakeFirst();
      // Processed by the payments worker (Razorpay refund API) — row is the durable intent.
      await tx.insertInto('refunds').values({
        paymentId: payment?.id ?? null, bookingId: b.id, amountPaise: b.amountPaidPaise,
        destination: payment ? 'source' : 'wallet', reason, initiatedBy: actorId, idempotencyKey: `booking-${to}:${b.id}`,
      }).onConflict((oc) => oc.column('idempotencyKey').doNothing()).execute();
    }
    await this.history(tx, b.id, b.status, to, actor, actorId, reason);
  }

  /** Freezes the settlement and credits the vendor ledger. */
  private async complete(tx: Tx, bookingId: string, actor: ActorKind, actorId: string | null, collectedOfflinePaise = 0) {
    const b = await tx.selectFrom('bookings').selectAll().where('id', '=', bookingId).forUpdate().executeTakeFirstOrThrow();
    const gross = b.finalTotalPaise ?? 0;
    const approved = await tx.selectFrom('bookingEstimates').select(['subtotalPaise']).where('bookingId', '=', b.id)
      .where('status', '=', 'approved').executeTakeFirst();
    let taxable: number;
    if (approved) {
      taxable = approved.subtotalPaise;                           // estimates are tax-exclusive
    } else {
      const svc = await tx.selectFrom('bookingServices').select(['pricePaise', 'gstRateBps']).where('bookingId', '=', b.id).execute();
      taxable = svc.reduce((s, x) => s + (x.pricePaise ?? 0) - taxFromInclusive(x.pricePaise ?? 0, x.gstRateBps), 0);
    }
    const commissionBps = await this.commissionBps(tx, b.vendorId, b.id);
    const st = settle(gross, taxable, commissionBps, {
      gstOnCommissionBps: this.env.GST_ON_COMMISSION_BPS, tcsBps: this.env.TCS_BPS, tdsBps: this.env.TDS_194O_BPS,
    });
    await tx.updateTable('bookings').set({
      status: 'completed', completedAt: new Date(), paymentState: 'paid',
      commissionBps, commissionPaise: st.commissionPaise, commissionGstPaise: st.commissionGstPaise,
      tcsPaise: st.tcsPaise, tdsPaise: st.tdsPaise, vendorPayoutPaise: st.vendorPayoutPaise,
    }).where('id', '=', b.id).execute();
    await this.history(tx, b.id, b.status, 'completed', actor, actorId);

    // The vendor already holds cash collected at the shop, so only the difference moves through the ledger.
    const net = st.vendorPayoutPaise - collectedOfflinePaise;
    if (net !== 0) {
      await tx.insertInto('vendorLedgerEntries').values({
        vendorId: b.vendorId, type: net > 0 ? 'booking_earning' : 'adjustment', amountPaise: net, bookingId: b.id,
        description: net > 0 ? `Booking ${b.bookingNumber}` : `Platform fees on cash collected for ${b.bookingNumber}`,
        availableAt: new Date(Date.now() + this.env.SERVICE_EARNING_HOLD_HOURS * 3600_000),
      }).execute();
    }
  }

  /** vendor override → newest category rule → newest domain rule. */
  private async commissionBps(tx: Tx, vendorId: string, bookingId: string): Promise<number> {
    const v = await tx.selectFrom('vendors').select('commissionBpsOverride').where('id', '=', vendorId).executeTakeFirstOrThrow();
    if (v.commissionBpsOverride != null) return v.commissionBpsOverride;
    const r = await sql<{ rateBps: number }>`
      SELECT r.rate_bps FROM booking_services bs
      JOIN services s ON s.id = bs.service_id
      JOIN subcategories sc ON sc.id = s.subcategory_id
      JOIN categories c ON c.id = sc.category_id
      JOIN commission_rules r ON r.domain = c.domain AND (r.category_id = c.id OR r.category_id IS NULL)
      WHERE bs.booking_id = ${bookingId} AND r.effective_from <= now() AND (r.effective_to IS NULL OR r.effective_to > now())
      ORDER BY (r.category_id IS NULL), r.effective_from DESC LIMIT 1`.execute(tx);
    return r.rows[0]?.rateBps ?? 1000;   // CamelCasePlugin maps rate_bps → rateBps on raw queries too
  }
}

/** Estimate lines are tax-exclusive; tax is computed per line. Only accepted lines count. */
export function estimateTotals(items: { quantity: number; unitPricePaise: number; gstRateBps: number; isAccepted: boolean }[]) {
  let subtotalPaise = 0;
  let taxPaise = 0;
  for (const i of items) {
    if (!i.isAccepted) continue;
    const line = Math.round(Number(i.quantity) * i.unitPricePaise);
    subtotalPaise += line;
    taxPaise += line > 0 ? bpsOf(line, i.gstRateBps) : -bpsOf(-line, i.gstRateBps);
  }
  return { subtotalPaise, taxPaise, totalPaise: subtotalPaise + taxPaise };
}
