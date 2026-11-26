import { Controller, Get, Module, Param, ParseIntPipe, Query } from '@nestjs/common';
import { ApiQuery, ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/auth';
import { Lang, Language, t } from '../../common/http';
import { Database, InjectDb } from '../../infra/db/database';
import type { BusinessDomain } from '../../infra/db/db.types';

/**
 * Reference data. Responses are deterministic for a given DB state, so Express's automatic weak ETag
 * makes `If-None-Match` revalidation return 304 with no body — cheap on slow mobile networks.
 */
@ApiTags('catalog')
@Public()
@Controller('catalog')
export class CatalogController {
  constructor(@InjectDb() private readonly db: Database) {}

  @Get('bootstrap')
  async bootstrap(@Language() lang: Lang) {
    const [categories, makes, brands] = await Promise.all([
      this.categories(lang),
      this.makesWithModels(),
      this.db.selectFrom('brands').select(['id', 'name', 'slug', 'logoUrl', 'isVehicleOem']).orderBy('name').execute(),
    ]);
    const version = await this.db.selectFrom('categories')
      .select((eb) => eb.fn.max('updatedAt').as('v')).executeTakeFirst();
    return {
      version: version?.v ?? null,
      categories, brands, makes,
      config: { minAppVersion: { android: '1.0.0', ios: '1.0.0' }, codMaxPaise: 500000, cities: ['Pune'] },
    };
  }

  @Get('categories')
  @ApiQuery({ name: 'domain', required: false, enum: ['parts', 'service', 'decor'] })
  categoriesEndpoint(@Language() lang: Lang, @Query('domain') domain?: BusinessDomain) {
    return this.categories(lang, domain);
  }

  @Get('brands')
  brands() {
    return this.db.selectFrom('brands').select(['id', 'name', 'slug', 'logoUrl', 'isVehicleOem']).orderBy('name').execute();
  }

  @Get('makes')
  makes() {
    return this.db.selectFrom('vehicleMakes').select(['id', 'name', 'slug', 'logoUrl'])
      .where('isActive', '=', true).orderBy('sortOrder').execute();
  }

  @Get('makes/:makeId/models')
  models(@Param('makeId', ParseIntPipe) makeId: number) {
    return this.db.selectFrom('vehicleModels').select(['id', 'name', 'slug', 'bodyType'])
      .where('makeId', '=', makeId).where('isActive', '=', true).orderBy('name').execute();
  }

  @Get('models/:modelId/variants')
  variants(@Param('modelId', ParseIntPipe) modelId: number) {
    return this.db.selectFrom('vehicleVariants')
      .select(['id', 'name', 'fuelType', 'transmission', 'engineCc', 'yearFrom', 'yearTo'])
      .where('modelId', '=', modelId).where('isActive', '=', true).orderBy('yearFrom', 'desc').execute();
  }

  private async categories(lang: Lang, domain?: BusinessDomain) {
    let q = this.db.selectFrom('categories').select(['id', 'domain', 'slug', 'nameI18n', 'iconUrl'])
      .where('isActive', '=', true).orderBy('domain').orderBy('sortOrder');
    if (domain) q = q.where('domain', '=', domain);
    const [cats, subs] = await Promise.all([
      q.execute(),
      this.db.selectFrom('subcategories').select(['id', 'categoryId', 'slug', 'nameI18n', 'iconUrl'])
        .where('isActive', '=', true).orderBy('sortOrder').execute(),
    ]);
    return cats.map((c) => ({
      id: c.id, domain: c.domain, slug: c.slug, name: t(c.nameI18n, lang), iconUrl: c.iconUrl,
      subcategories: subs.filter((s) => s.categoryId === c.id)
        .map((s) => ({ id: s.id, slug: s.slug, name: t(s.nameI18n, lang), iconUrl: s.iconUrl })),
    }));
  }

  private async makesWithModels() {
    const [makes, models] = await Promise.all([
      this.makes(),
      this.db.selectFrom('vehicleModels').select(['id', 'makeId', 'name', 'bodyType']).where('isActive', '=', true).orderBy('name').execute(),
    ]);
    return makes.map((m) => ({ ...m, models: models.filter((x) => x.makeId === m.id).map(({ makeId: _, ...rest }) => rest) }));
  }
}

@Module({ controllers: [CatalogController] })
export class CatalogModule {}
