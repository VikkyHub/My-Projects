import { Body, Controller, Get, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsBoolean, IsIn, IsInt, IsLatitude, IsLongitude, IsOptional, IsString, IsUrl, IsUUID,
  Matches, Max, MaxLength, Min, MinLength, ValidateNested,
} from 'class-validator';
import { AuthContext, CurrentVendor, OptionalUser, Public, VendorContext, VendorRole } from '../../common/auth';
import { Errors } from '../../common/errors';
import { decodeCursor, page } from '../../common/http';
import { Database, InjectDb } from '../../infra/db/database';
import type { ItemCondition, ListingStatus, PartType } from '../../infra/db/db.types';
import { cdn, ProductsService } from './products.service';

const csvInts = ({ value }: { value: unknown }) =>
  value == null || value === '' ? undefined : String(value).split(',').map((x) => Number(x.trim()));
const csv = ({ value }: { value: unknown }) => (value == null || value === '' ? undefined : String(value).split(',').map((x) => x.trim()));
const bool = ({ value }: { value: unknown }) => (value === 'true' ? true : value === 'false' ? false : value);
const PART_TYPES = ['oem', 'oes', 'aftermarket'];
const CONDITIONS = ['new', 'refurbished', 'used'];
const SORTS = ['relevance', 'price_asc', 'price_desc', 'rating', 'nearest', 'newest'] as const;

export class ProductSearchQuery {
  @ApiPropertyOptional({ example: 'brake pad' }) @IsOptional() @IsString() @MaxLength(80) q?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() vehicleId?: string;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() makeId?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() modelId?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(1950) @Max(2100) year?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() subcategoryId?: number;
  @ApiPropertyOptional({ description: 'comma separated', example: '5,13' }) @IsOptional() @Transform(csvInts) @IsInt({ each: true }) brandId?: number[];
  @ApiPropertyOptional({ description: 'comma separated: oem,oes,aftermarket' }) @IsOptional() @Transform(csv) @IsIn(PART_TYPES, { each: true }) partType?: PartType[];
  @ApiPropertyOptional({ enum: CONDITIONS }) @IsOptional() @IsIn(CONDITIONS) condition?: ItemCondition;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(0) minPricePaise?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(0) maxPricePaise?: number;
  @ApiPropertyOptional({ default: true }) @IsOptional() @Transform(bool) @IsBoolean() inStock?: boolean;
  @ApiPropertyOptional({ example: 18.5204 }) @IsOptional() @Type(() => Number) @IsLatitude() lat?: number;
  @ApiPropertyOptional({ example: 73.8567 }) @IsOptional() @Type(() => Number) @IsLongitude() lng?: number;
  @ApiPropertyOptional({ enum: SORTS }) @IsOptional() @IsIn(SORTS) sort?: (typeof SORTS)[number];
  @ApiPropertyOptional() @IsOptional() @IsString() cursor?: string;
  @ApiPropertyOptional({ default: 20 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
}

@ApiTags('products')
@Public()
@Controller('products')
export class ProductsController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  search(@Query() q: ProductSearchQuery, @OptionalUser() user?: AuthContext) {
    return this.products.search(user?.userId, { ...q, brandIds: q.brandId, partTypes: q.partType });
  }

  @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string, @Query('vehicleId') vehicleId: string | undefined, @OptionalUser() user?: AuthContext) {
    return this.products.detail(id, user?.userId, vehicleId || undefined);
  }
}

// ---------------- vendor inventory ----------------

class FitmentDto {
  @ApiProperty() @IsInt() makeId: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() modelId?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() variantId?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1950) @Max(2100) yearFrom?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1950) @Max(2100) yearTo?: number;
}
class ImageDto {
  @ApiProperty() @IsUrl({ protocols: ['https'], require_protocol: true }) url: string;
  @ApiProperty() @IsString() @MaxLength(200) publicId: string;
}
class CreateProductDto {
  @ApiProperty() @IsInt() subcategoryId: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() brandId?: number;
  @ApiProperty({ example: 'BP-SW-01' }) @IsString() @MinLength(1) @MaxLength(40) @Matches(/^[A-Za-z0-9._-]+$/) sku: string;
  @ApiProperty() @IsString() @MinLength(3) @MaxLength(140) name: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(4000) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) partNumber?: string;
  @ApiProperty({ enum: PART_TYPES }) @IsIn(PART_TYPES) partType: PartType;
  @ApiPropertyOptional({ enum: CONDITIONS }) @IsOptional() @IsIn(CONDITIONS) condition?: ItemCondition;
  @ApiProperty({ example: 180000 }) @IsInt() @Min(100) mrpPaise: number;
  @ApiProperty({ example: 149900 }) @IsInt() @Min(100) pricePaise: number;
  @ApiProperty({ example: 1800 }) @IsInt() @Min(0) @Max(4000) gstRateBps: number;
  @ApiProperty({ example: '87083000' }) @Matches(/^[0-9]{4,8}$/) hsnCode: string;
  @ApiProperty() @IsInt() @Min(0) @Max(100000) stockQty: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) lowStockThreshold?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(100) maxPerOrder?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(120) warrantyMonths?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(30) returnWindowDays?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isUniversalFit?: boolean;
  @ApiPropertyOptional({ enum: ['draft', 'active', 'inactive'] }) @IsOptional() @IsIn(['draft', 'active', 'inactive']) status?: ListingStatus;
  @ApiPropertyOptional({ type: [FitmentDto] }) @IsOptional() @IsArray() @ArrayMaxSize(100) @ValidateNested({ each: true }) @Type(() => FitmentDto) fitments?: FitmentDto[];
  @ApiPropertyOptional({ type: [ImageDto] }) @IsOptional() @IsArray() @ArrayMaxSize(8) @ValidateNested({ each: true }) @Type(() => ImageDto) images?: ImageDto[];
}

@ApiTags('vendor')
@ApiBearerAuth()
@ApiHeader({ name: 'X-Vendor-Id', required: true })
@Controller('vendor/products')
export class VendorProductsController {
  constructor(@InjectDb() private readonly db: Database) {}

  @Get() @VendorRole('staff')
  async list(@CurrentVendor() vendor: VendorContext, @Query('q') q?: string, @Query('lowStock') lowStock?: string, @Query('cursor') cursor?: string) {
    const offset = decodeCursor(cursor);
    const rows = await this.db.selectFrom('products as p')
      .select(['p.id', 'p.sku', 'p.name', 'p.partNumber', 'p.pricePaise', 'p.mrpPaise', 'p.stockQty', 'p.reservedQty',
        'p.lowStockThreshold', 'p.status', 'p.ratingAvg', 'p.ratingCount', 'p.updatedAt',
        (eb) => eb.selectFrom('productImages as i').select('i.url').whereRef('i.productId', '=', 'p.id').orderBy('i.sortOrder').limit(1).as('imageUrl')])
      .where('p.vendorId', '=', vendor.id).where('p.deletedAt', 'is', null)
      .$if(!!q, (qb) => qb.where((eb) => eb.or([eb('p.name', 'ilike', `%${q}%`), eb('p.sku', 'ilike', `%${q}%`), eb('p.partNumber', 'ilike', `%${q}%`)])))
      .$if(lowStock === 'true', (qb) => qb.whereRef('p.stockQty', '<=', 'p.lowStockThreshold'))
      .orderBy('p.updatedAt', 'desc').limit(21).offset(offset).execute();
    const res = page(rows, offset, 20);
    return { ...res, data: res.data.map((r) => ({ ...r, thumbnailUrl: cdn(r.imageUrl, 160), imageUrl: undefined })) };
  }

  @Post() @VendorRole('manager')
  async create(@CurrentVendor() vendor: VendorContext, @Body() dto: CreateProductDto) {
    if (dto.pricePaise > dto.mrpPaise) throw Errors.validation({ pricePaise: 'cannot be more than MRP' });
    const status = dto.status ?? 'draft';
    if (status === 'active') {
      if (!dto.images?.length) throw Errors.validation({ images: 'add at least one photo before publishing' });
      if (!dto.isUniversalFit && !dto.fitments?.length) throw Errors.validation({ fitments: 'add vehicles this part fits, or mark it universal' });
    }
    const v = await this.db.selectFrom('vendors').select('businessDomains').where('id', '=', vendor.id).executeTakeFirstOrThrow();
    if (!v.businessDomains.includes('parts')) throw Errors.forbidden('Your shop is not registered to sell parts.');
    const sub = await this.db.selectFrom('subcategories as s').innerJoin('categories as c', 'c.id', 's.categoryId')
      .select('c.domain').where('s.id', '=', dto.subcategoryId).executeTakeFirst();
    if (sub?.domain !== 'parts') throw Errors.validation({ subcategoryId: 'must be a spare-parts subcategory' });

    const dup = await this.db.selectFrom('products').select('id').where('vendorId', '=', vendor.id)
      .where('sku', '=', dto.sku).where('deletedAt', 'is', null).executeTakeFirst();
    if (dup) throw Errors.conflict('CONFLICT', `SKU ${dto.sku} already exists in your inventory.`);

    return this.db.transaction().execute(async (tx) => {
      const p = await tx.insertInto('products').values({
        vendorId: vendor.id, subcategoryId: dto.subcategoryId, brandId: dto.brandId ?? null, sku: dto.sku, name: dto.name,
        description: dto.description ?? null, partNumber: dto.partNumber?.toUpperCase().replace(/\s+/g, '') ?? null,
        partType: dto.partType, condition: dto.condition ?? 'new', mrpPaise: dto.mrpPaise, pricePaise: dto.pricePaise,
        gstRateBps: dto.gstRateBps, hsnCode: dto.hsnCode, stockQty: dto.stockQty,
        lowStockThreshold: dto.lowStockThreshold ?? 3, maxPerOrder: dto.maxPerOrder ?? 10,
        warrantyMonths: dto.warrantyMonths ?? 0, returnWindowDays: dto.returnWindowDays ?? 7,
        isUniversalFit: dto.isUniversalFit ?? false, status,
      }).returning(['id', 'sku', 'name', 'status']).executeTakeFirstOrThrow();
      if (dto.fitments?.length) {
        await tx.insertInto('productFitments').values(dto.fitments.map((f) => ({
          productId: p.id, makeId: f.makeId, modelId: f.modelId ?? null, variantId: f.variantId ?? null,
          yearFrom: f.yearFrom ?? null, yearTo: f.yearTo ?? null,
        }))).execute();
      }
      if (dto.images?.length) {
        await tx.insertInto('productImages').values(dto.images.map((img, i) => ({ productId: p.id, url: img.url, publicId: img.publicId, sortOrder: i }))).execute();
      }
      if (dto.stockQty > 0) {
        await tx.insertInto('inventoryMovements').values({ productId: p.id, delta: dto.stockQty, reason: 'restock', note: 'Initial stock' }).execute();
      }
      return p;
    });
  }
}

@Module({ controllers: [ProductsController, VendorProductsController], providers: [ProductsService] })
export class ProductsModule {}
