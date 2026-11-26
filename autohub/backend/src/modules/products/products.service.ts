import { Injectable } from '@nestjs/common';
import { RawBuilder, sql } from 'kysely';
import { Errors } from '../../common/errors';
import { decodeCursor, IST_OFFSET_MINUTES, page } from '../../common/http';
import { Database, InjectDb } from '../../infra/db/database';
import type { FuelType, ItemCondition, PartType } from '../../infra/db/db.types';

export interface ProductSearch {
  q?: string; vehicleId?: string; makeId?: number; modelId?: number; year?: number;
  subcategoryId?: number; brandIds?: number[]; partTypes?: PartType[]; condition?: ItemCondition;
  minPricePaise?: number; maxPricePaise?: number; inStock?: boolean;
  lat?: number; lng?: number; vendorId?: string;
  sort?: 'relevance' | 'price_asc' | 'price_desc' | 'rating' | 'nearest' | 'newest';
  cursor?: string; limit?: number;
}

interface VehicleFit { makeId: number; modelId: number | null; variantId: number | null; year: number | null; fuelType: FuelType | null }

/** Cloudinary on-the-fly resize: low-end phones download a 320px WebP instead of the original. */
export function cdn(url: string | null | undefined, width: number): string | null {
  if (!url) return null;
  return url.includes('/image/upload/') ? url.replace('/image/upload/', `/image/upload/f_auto,q_auto,w_${width}/`) : url;
}

/** "brak pad" → brak:* & pad:*  (prefix match while typing). Only letters/digits survive. */
function prefixTsQuery(q: string): string | null {
  const words = q.toLowerCase().match(/[\p{L}\p{N}]+/gu)?.slice(0, 6) ?? [];
  return words.length ? words.map((w) => `${w}:*`).join(' & ') : null;
}

@Injectable()
export class ProductsService {
  constructor(@InjectDb() private readonly db: Database) {}

  async resolveVehicle(userId: string | undefined, s: ProductSearch): Promise<VehicleFit | null> {
    if (s.vehicleId) {
      if (!userId) throw Errors.unauthenticated('Log in to filter by your saved vehicle.');
      const v = await this.db.selectFrom('vehicles').select(['makeId', 'modelId', 'variantId', 'manufactureYear', 'fuelType'])
        .where('id', '=', s.vehicleId).where('userId', '=', userId).where('deletedAt', 'is', null).executeTakeFirst();
      if (!v) throw Errors.notFound('Vehicle');
      return { makeId: v.makeId, modelId: v.modelId, variantId: v.variantId, year: v.manufactureYear, fuelType: v.fuelType };
    }
    if (s.makeId) return { makeId: s.makeId, modelId: s.modelId ?? null, variantId: null, year: s.year ?? null, fuelType: null };
    return null;
  }

  /** SQL boolean: product p has a fitment row covering this vehicle. Broader rows (make-only) also match. */
  private fitsVehicle(v: VehicleFit): RawBuilder<boolean> {
    return sql<boolean>`EXISTS (
      SELECT 1 FROM product_fitments f
      WHERE f.product_id = p.id AND f.make_id = ${v.makeId}
        AND (f.model_id IS NULL OR f.model_id = ${v.modelId})
        AND (f.variant_id IS NULL OR f.variant_id = ${v.variantId})
        AND (f.fuel_type IS NULL OR ${v.fuelType}::fuel_type IS NULL OR f.fuel_type = ${v.fuelType}::fuel_type)
        AND (${v.year}::int IS NULL OR ${v.year}::int BETWEEN coalesce(f.year_from, 1950) AND coalesce(f.year_to, 2100)))`;
  }

  async search(userId: string | undefined, s: ProductSearch) {
    const limit = Math.min(Math.max(s.limit ?? 20, 1), 50);
    const offset = decodeCursor(s.cursor);
    const vehicle = await this.resolveVehicle(userId, s);
    const point = s.lat != null && s.lng != null ? sql`ST_SetSRID(ST_MakePoint(${s.lng}, ${s.lat}), 4326)::geography` : null;
    const tsq = s.q ? prefixTsQuery(s.q) : null;

    const where: RawBuilder<unknown>[] = [
      sql`p.status = 'active'`, sql`p.deleted_at IS NULL`,
      sql`v.status = 'approved'`, sql`v.deleted_at IS NULL`, sql`v.is_accepting_orders`,
    ];
    if (s.q) {
      where.push(sql`(${tsq ? sql`p.search_vector @@ to_tsquery('simple', ${tsq})` : sql`false`}
        OR p.name ILIKE ${'%' + s.q.replace(/[%_\\]/g, '') + '%'}
        OR upper(p.part_number) = upper(${s.q.replace(/\s+/g, '')}))`);
    }
    if (vehicle) where.push(sql`(p.is_universal_fit OR ${this.fitsVehicle(vehicle)})`);
    if (s.subcategoryId) where.push(sql`p.subcategory_id = ${s.subcategoryId}`);
    if (s.brandIds?.length) where.push(sql`p.brand_id = ANY(${s.brandIds}::int[])`);
    if (s.partTypes?.length) where.push(sql`p.part_type = ANY(${s.partTypes}::part_type[])`);
    if (s.condition) where.push(sql`p.condition = ${s.condition}::item_condition`);
    if (s.minPricePaise != null) where.push(sql`p.price_paise >= ${s.minPricePaise}`);
    if (s.maxPricePaise != null) where.push(sql`p.price_paise <= ${s.maxPricePaise}`);
    if (s.inStock ?? true) where.push(sql`p.stock_qty - p.reserved_qty > 0`);
    if (s.vendorId) where.push(sql`p.vendor_id = ${s.vendorId}`);
    // Only shops that deliver to the customer's location (default radius 10 km).
    if (point && !s.vendorId) where.push(sql`ST_DWithin(v.location, ${point}, coalesce(v.delivery_radius_km, 10) * 1000)`);

    const rank = tsq ? sql`ts_rank(p.search_vector, to_tsquery('simple', ${tsq}))` : sql`0`;
    const distance = point ? sql`ST_Distance(v.location, ${point}) / 1000` : sql`NULL::float8`;
    const orderBy = {
      relevance: sql`rank DESC, p.rating_count DESC, p.id`,
      price_asc: sql`p.price_paise ASC, p.id`,
      price_desc: sql`p.price_paise DESC, p.id`,
      rating: sql`p.rating_avg DESC, p.rating_count DESC, p.id`,
      nearest: point ? sql`distance_km ASC NULLS LAST, p.id` : sql`p.id`,
      newest: sql`p.created_at DESC, p.id`,
    }[s.sort ?? 'relevance'];
    const fit = vehicle
      ? sql`CASE WHEN p.is_universal_fit THEN 'universal' WHEN ${this.fitsVehicle(vehicle)} THEN 'fits'
                 WHEN EXISTS (SELECT 1 FROM product_fitments f2 WHERE f2.product_id = p.id) THEN 'does_not_fit' ELSE 'unknown' END`
      : sql`NULL`;

    const filtered = sql`
      SELECT p.id, p.name, p.part_number, p.part_type, p.condition, p.mrp_paise, p.price_paise, p.brand_id,
             p.rating_avg, p.rating_count, p.created_at, p.stock_qty - p.reserved_qty AS available,
             b.name AS brand_name, v.id AS vendor_id, v.business_name, v.rating_avg AS vendor_rating,
             ${rank} AS rank, ${distance} AS distance_km, ${fit} AS fit,
             (SELECT url FROM product_images i WHERE i.product_id = p.id AND i.moderation = 'approved'
               ORDER BY sort_order LIMIT 1) AS image_url
      FROM products p
      JOIN vendors v ON v.id = p.vendor_id
      LEFT JOIN brands b ON b.id = p.brand_id
      WHERE ${sql.join(where, sql` AND `)}`;

    const [rows, facets] = await Promise.all([
      sql<any>`SELECT * FROM (${filtered}) p ORDER BY ${orderBy} LIMIT ${limit + 1} OFFSET ${offset}`.execute(this.db),
      sql<any>`WITH f AS (${filtered})
        SELECT
          (SELECT coalesce(json_agg(x ORDER BY x.count DESC), '[]') FROM
             (SELECT brand_id AS id, brand_name AS name, count(*)::int AS count FROM f WHERE brand_id IS NOT NULL GROUP BY 1, 2) x) AS brands,
          (SELECT coalesce(json_object_agg(part_type, n), '{}') FROM (SELECT part_type, count(*)::int AS n FROM f GROUP BY 1) y) AS part_type,
          (SELECT json_build_object('min', min(price_paise), 'max', max(price_paise)) FROM f) AS price_range_paise,
          (SELECT count(*)::int FROM f) AS total`.execute(this.db),
    ]);

    // Same-day delivery for orders placed before 5 pm IST.
    const minutesIntoIstDay = (Math.floor(Date.now() / 60_000) + IST_OFFSET_MINUTES) % 1440;
    const afterCutoff = minutesIntoIstDay >= 17 * 60;
    const result = page(rows.rows, offset, limit);
    return {
      ...result,
      data: result.data.map((r: any) => ({
        id: r.id, name: r.name,
        brand: r.brandId ? { id: r.brandId, name: r.brandName } : null,
        partNumber: r.partNumber, partType: r.partType, condition: r.condition,
        mrpPaise: r.mrpPaise, pricePaise: r.pricePaise,
        discountPercent: Math.floor(((r.mrpPaise - r.pricePaise) * 100) / r.mrpPaise),
        thumbnailUrl: cdn(r.imageUrl, 320),
        rating: { avg: Number(r.ratingAvg), count: r.ratingCount },
        inStock: r.available > 0,
        fit: r.fit,
        vendor: { id: r.vendorId, businessName: r.businessName, rating: Number(r.vendorRating),
                  distanceKm: r.distanceKm == null ? null : Math.round(r.distanceKm * 10) / 10 },
        deliveryEta: r.distanceKm == null ? null : afterCutoff ? 'tomorrow' : 'today',
      })),
      facets: { brands: facets.rows[0].brands, partType: facets.rows[0].partType, priceRangePaise: facets.rows[0].priceRangePaise },
      total: facets.rows[0].total,
    };
  }

  async detail(id: string, userId: string | undefined, vehicleId?: string) {
    const p = await this.db.selectFrom('products as p')
      .innerJoin('vendors as v', 'v.id', 'p.vendorId')
      .innerJoin('subcategories as sc', 'sc.id', 'p.subcategoryId')
      .leftJoin('brands as b', 'b.id', 'p.brandId')
      .select([
        'p.id', 'p.sku', 'p.name', 'p.description', 'p.partNumber', 'p.partType', 'p.condition',
        'p.mrpPaise', 'p.pricePaise', 'p.gstRateBps', 'p.hsnCode', 'p.stockQty', 'p.reservedQty',
        'p.lowStockThreshold', 'p.maxPerOrder', 'p.warrantyMonths', 'p.returnWindowDays', 'p.isUniversalFit',
        'p.ratingAvg', 'p.ratingCount', 'p.brandId', 'b.name as brandName',
        'sc.id as subcategoryId', 'sc.nameI18n as subcategoryName', 'sc.categoryId',
        'v.id as vendorId', 'v.businessName', 'v.ratingAvg as vendorRating', 'v.codEnabled', 'v.phone as vendorPhone',
      ])
      .where('p.id', '=', id).where('p.status', '=', 'active').where('p.deletedAt', 'is', null)
      .where('v.status', '=', 'approved')
      .executeTakeFirst();
    if (!p) throw Errors.notFound('Product');

    const [images, fitments, distribution, otherSellers] = await Promise.all([
      this.db.selectFrom('productImages').select(['url']).where('productId', '=', id).where('moderation', '=', 'approved')
        .orderBy('sortOrder').execute(),
      this.db.selectFrom('productFitments as f').innerJoin('vehicleMakes as mk', 'mk.id', 'f.makeId')
        .leftJoin('vehicleModels as md', 'md.id', 'f.modelId').leftJoin('vehicleVariants as vr', 'vr.id', 'f.variantId')
        .select(['mk.name as make', 'md.name as model', 'vr.name as variant', 'f.fuelType', 'f.yearFrom', 'f.yearTo'])
        .where('f.productId', '=', id).execute(),
      this.db.selectFrom('reviews').select(['rating', (eb) => eb.fn.countAll<number>().as('n')])
        .where('productId', '=', id).where('status', '=', 'published').groupBy('rating').execute(),
      p.partNumber
        ? this.db.selectFrom('products as o').innerJoin('vendors as ov', 'ov.id', 'o.vendorId')
            .select(['o.id as productId', 'ov.businessName as vendorName', 'o.pricePaise'])
            .where('o.partNumber', '=', p.partNumber).where('o.id', '!=', id).where('o.status', '=', 'active')
            .where('o.deletedAt', 'is', null).where('ov.status', '=', 'approved')
            .$if(p.brandId != null, (q) => q.where('o.brandId', '=', p.brandId!))
            .orderBy('o.pricePaise').limit(5).execute()
        : Promise.resolve([]),
    ]);

    let fitForVehicle: { vehicleId: string; fit: string } | null = null;
    if (vehicleId) {
      const v = await this.resolveVehicle(userId, { vehicleId });
      const r = await sql<{ fit: string }>`SELECT CASE WHEN p.is_universal_fit THEN 'universal'
          WHEN ${this.fitsVehicle(v!)} THEN 'fits'
          WHEN EXISTS (SELECT 1 FROM product_fitments f2 WHERE f2.product_id = p.id) THEN 'does_not_fit' ELSE 'unknown' END AS fit
        FROM products p WHERE p.id = ${id}`.execute(this.db);
      fitForVehicle = { vehicleId, fit: r.rows[0].fit };
    }

    const available = p.stockQty - p.reservedQty;
    return {
      id: p.id, sku: p.sku, name: p.name, description: p.description,
      brand: p.brandId ? { id: p.brandId, name: p.brandName } : null,
      partNumber: p.partNumber, partType: p.partType, condition: p.condition,
      subcategory: { id: p.subcategoryId, name: (p.subcategoryName as Record<string, string>).en, categoryId: p.categoryId },
      mrpPaise: p.mrpPaise, pricePaise: p.pricePaise, gstRateBps: p.gstRateBps, hsnCode: p.hsnCode,
      stock: { inStock: available > 0, lowStock: available > 0 && available <= p.lowStockThreshold, maxPerOrder: Math.min(p.maxPerOrder, Math.max(available, 0)) },
      warrantyMonths: p.warrantyMonths, returnWindowDays: p.returnWindowDays,
      images: images.map((i) => ({ url: cdn(i.url, 800), thumbUrl: cdn(i.url, 320) })),
      fitments, isUniversalFit: p.isUniversalFit, fitForVehicle,
      rating: {
        avg: Number(p.ratingAvg), count: p.ratingCount,
        distribution: Object.fromEntries([5, 4, 3, 2, 1].map((n) => [n, Number(distribution.find((d) => d.rating === n)?.n ?? 0)])),
      },
      vendor: { id: p.vendorId, businessName: p.businessName, rating: Number(p.vendorRating), codEnabled: p.codEnabled, phone: p.vendorPhone },
      otherSellers,
    };
  }
}
