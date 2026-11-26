import { Controller, Get, Module, Param, ParseUUIDPipe, Query } from '@nestjs/common';
import { ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, IsUUID, Matches, Max, Min } from 'class-validator';
import { sql } from 'kysely';
import { AuthContext, OptionalUser, Public } from '../../common/auth';
import { Errors } from '../../common/errors';
import { decodeCursor, istDate, istMidnight, istTime, Lang, Language, page, t } from '../../common/http';
import { Database, InjectDb } from '../../infra/db/database';
import type { BusinessDomain } from '../../infra/db/db.types';
import { cdn } from '../products/products.service';

const bool = ({ value }: { value: unknown }) => (value === 'true' ? true : value === 'false' ? false : value);

class NearbyQuery {
  @ApiPropertyOptional({ example: 18.5204 }) @Type(() => Number) @IsLatitude() lat: number;
  @ApiPropertyOptional({ example: 73.8567 }) @Type(() => Number) @IsLongitude() lng: number;
  @ApiPropertyOptional({ default: 10 }) @IsOptional() @Type(() => Number) @IsNumber() @Min(0.5) @Max(50) radiusKm?: number;
  @ApiPropertyOptional({ enum: ['parts', 'service', 'decor'] }) @IsOptional() @IsIn(['parts', 'service', 'decor']) domain?: BusinessDomain;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() subcategoryId?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsNumber() @Min(0) @Max(5) minRating?: number;
  @ApiPropertyOptional() @IsOptional() @Transform(bool) @IsBoolean() openNow?: boolean;
  @ApiPropertyOptional() @IsOptional() @Transform(bool) @IsBoolean() doorstep?: boolean;
  @ApiPropertyOptional({ enum: ['distance', 'rating', 'price'] }) @IsOptional() @IsIn(['distance', 'rating', 'price']) sort?: 'distance' | 'rating' | 'price';
  @ApiPropertyOptional() @IsOptional() @IsString() cursor?: string;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
}

class ServicesQuery {
  @ApiPropertyOptional({ enum: ['service', 'decor'] }) @IsOptional() @IsIn(['service', 'decor']) domain?: BusinessDomain;
  @ApiPropertyOptional() @IsOptional() @IsUUID() vehicleId?: string;
}

class SlotsQuery {
  @ApiPropertyOptional({ example: '2026-12-01' }) @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) date?: string;
}

/** Open right now in IST, from the weekly working-hours template. */
const openNowSql = sql<boolean>`EXISTS (
  SELECT 1 FROM vendor_working_hours h
  WHERE h.vendor_id = v.id
    AND h.weekday = extract(dow FROM now() AT TIME ZONE 'Asia/Kolkata')
    AND (now() AT TIME ZONE 'Asia/Kolkata')::time BETWEEN h.opens_at AND h.closes_at)
  AND NOT EXISTS (SELECT 1 FROM vendor_holidays hd WHERE hd.vendor_id = v.id AND hd.day = (now() AT TIME ZONE 'Asia/Kolkata')::date)`;

@ApiTags('vendors')
@Public()
@Controller('vendors')
export class VendorsController {
  constructor(@InjectDb() private readonly db: Database) {}

  @Get('nearby')
  async nearby(@Query() q: NearbyQuery) {
    const limit = q.limit ?? 20;
    const offset = decodeCursor(q.cursor);
    const point = sql`ST_SetSRID(ST_MakePoint(${q.lng}, ${q.lat}), 4326)::geography`;
    const where = [
      sql`v.status = 'approved'`, sql`v.deleted_at IS NULL`,
      sql`ST_DWithin(v.location, ${point}, ${(q.radiusKm ?? 10) * 1000})`,
    ];
    if (q.domain) where.push(sql`${q.domain}::business_domain = ANY(v.business_domains)`);
    if (q.minRating != null) where.push(sql`v.rating_avg >= ${q.minRating}`);
    if (q.doorstep) where.push(sql`v.offers_doorstep`);
    if (q.openNow) where.push(openNowSql);
    const highlight = q.subcategoryId
      ? sql`(SELECT json_build_object('serviceName', s.name, 'fromPricePaise', s.price_paise) FROM services s
              WHERE s.vendor_id = v.id AND s.subcategory_id = ${q.subcategoryId} AND s.status = 'active' AND s.deleted_at IS NULL
              ORDER BY s.price_paise NULLS LAST LIMIT 1)`
      : sql`NULL::json`;
    if (q.subcategoryId) where.push(sql`${highlight} IS NOT NULL`);
    const order = q.sort === 'rating' ? sql`v.rating_avg DESC, distance_m`
      : q.sort === 'price' && q.subcategoryId ? sql`(highlight->>'fromPricePaise')::int NULLS LAST, distance_m`
      : sql`distance_m`;

    const rows = await sql<any>`
      SELECT v.id, v.slug, v.business_name, v.business_domains, v.logo_url, v.cover_url,
             ST_Y(v.location::geometry) AS lat, ST_X(v.location::geometry) AS lng,
             ST_Distance(v.location, ${point}) AS distance_m,
             v.address_line1, v.city, v.pincode, v.rating_avg, v.rating_count, v.offers_doorstep,
             ${openNowSql} AS is_open_now, ${highlight} AS highlight
      FROM vendors v WHERE ${sql.join(where, sql` AND `)}
      ORDER BY ${order} LIMIT ${limit + 1} OFFSET ${offset}`.execute(this.db);
    const res = page(rows.rows, offset, limit);
    return {
      ...res,
      data: res.data.map((r: any) => ({
        id: r.id, slug: r.slug, businessName: r.businessName, domains: r.businessDomains,
        logoUrl: cdn(r.logoUrl, 160), coverUrl: cdn(r.coverUrl, 640),
        location: { lat: r.lat, lng: r.lng }, distanceKm: Math.round(r.distanceM / 100) / 10,
        address: `${r.addressLine1}, ${r.city} ${r.pincode}`,
        rating: { avg: Number(r.ratingAvg), count: r.ratingCount },
        isOpenNow: r.isOpenNow, offersDoorstep: r.offersDoorstep, highlight: r.highlight,
      })),
    };
  }

  @Get(':id')
  async profile(@Param('id') idOrSlug: string) {
    const isUuid = /^[0-9a-f-]{36}$/i.test(idOrSlug);
    const v = await this.db.selectFrom('vendors')
      .select(['id', 'slug', 'businessName', 'description', 'businessDomains', 'phone', 'whatsappPhone', 'addressLine1',
        'addressLine2', 'city', 'state', 'pincode', 'logoUrl', 'coverUrl', 'openingHours', 'ratingAvg', 'ratingCount',
        'offersDoorstep', 'codEnabled', 'deliveryRadiusKm', 'isAcceptingOrders',
        sql<number>`ST_Y(location::geometry)`.as('lat'), sql<number>`ST_X(location::geometry)`.as('lng')])
      .where(isUuid ? 'id' : 'slug', '=', idOrSlug).where('status', '=', 'approved').where('deletedAt', 'is', null)
      .executeTakeFirst();
    if (!v) throw Errors.notFound('Shop');
    const hours = await this.db.selectFrom('vendorWorkingHours').select(['weekday', 'opensAt', 'closesAt'])
      .where('vendorId', '=', v.id).orderBy('weekday').orderBy('opensAt').execute();
    const { lat, lng, ...rest } = v;
    return { ...rest, ratingAvg: Number(v.ratingAvg), location: { lat, lng }, workingHours: hours,
      logoUrl: cdn(v.logoUrl, 240), coverUrl: cdn(v.coverUrl, 960) };
  }

  @Get(':id/services')
  async services(@Param('id', ParseUUIDPipe) id: string, @Query() q: ServicesQuery, @Language() lang: Lang, @OptionalUser() user?: AuthContext) {
    let vehicle: { fuelType: string; bodyType: string | null } | undefined;
    if (q.vehicleId) {
      if (!user) throw Errors.unauthenticated();
      vehicle = await this.db.selectFrom('vehicles as ve').innerJoin('vehicleModels as m', 'm.id', 've.modelId')
        .select(['ve.fuelType', 'm.bodyType']).where('ve.id', '=', q.vehicleId).where('ve.userId', '=', user.userId).executeTakeFirst();
      if (!vehicle) throw Errors.notFound('Vehicle');
    }
    const rows = await this.db.selectFrom('services as s')
      .innerJoin('subcategories as sc', 'sc.id', 's.subcategoryId').innerJoin('categories as c', 'c.id', 'sc.categoryId')
      .select(['s.id', 's.name', 's.description', 's.inclusions', 's.priceType', 's.pricePaise', 's.gstRateBps',
        's.durationMinutes', 's.warrantyDays', 's.advancePaise', 's.doorstepAvailable', 's.ratingAvg', 's.ratingCount',
        's.applicableFuelTypes', 's.applicableBodyTypes', 'sc.id as subcategoryId', 'sc.nameI18n as subName', 'c.domain',
        (eb) => eb.selectFrom('serviceImages as i').select('i.url').whereRef('i.serviceId', '=', 's.id').orderBy('i.sortOrder').limit(1).as('imageUrl')])
      .where('s.vendorId', '=', id).where('s.status', '=', 'active').where('s.deletedAt', 'is', null)
      .$if(!!q.domain, (qb) => qb.where('c.domain', '=', q.domain!))
      .orderBy('sc.sortOrder').orderBy('s.pricePaise').execute();
    return rows
      .filter((s) => !vehicle || (
        (!s.applicableFuelTypes || (s.applicableFuelTypes as string[]).includes(vehicle.fuelType)) &&
        (!s.applicableBodyTypes || !vehicle.bodyType || s.applicableBodyTypes.includes(vehicle.bodyType))))
      .map(({ subName, imageUrl, applicableFuelTypes: _f, applicableBodyTypes: _b, ...s }) => ({
        ...s, ratingAvg: Number(s.ratingAvg), subcategoryName: t(subName, lang), imageUrl: cdn(imageUrl, 480),
      }));
  }

  @Get(':id/slots')
  async slots(@Param('id', ParseUUIDPipe) id: string, @Query() q: SlotsQuery) {
    const date = q.date ?? istDate();
    const from = istMidnight(date);
    const to = new Date(from.getTime() + 86400_000);
    const earliest = new Date(Date.now() + 30 * 60_000);    // at least 30 minutes' notice
    const slots = await this.db.selectFrom('vendorSlots').select(['id', 'startsAt', 'endsAt', 'capacity', 'bookedCount'])
      .where('vendorId', '=', id).where('isBlocked', '=', false)
      .where('startsAt', '>=', from).where('startsAt', '<', to).where('startsAt', '>', earliest)
      .orderBy('startsAt').execute();
    const next = await this.db.selectFrom('vendorSlots').select('startsAt')
      .where('vendorId', '=', id).where('isBlocked', '=', false).where('startsAt', '>', earliest)
      .whereRef('bookedCount', '<', 'capacity').orderBy('startsAt').limit(1).executeTakeFirst();
    return {
      date, timezone: 'Asia/Kolkata',
      slots: slots.map((s) => ({ id: s.id, startsAt: s.startsAt, endsAt: s.endsAt, localTime: istTime(s.startsAt), available: s.capacity - s.bookedCount })),
      nextAvailableDate: next ? istDate(next.startsAt) : null,
    };
  }
}

@Module({ controllers: [VendorsController] })
export class VendorsModule {}
