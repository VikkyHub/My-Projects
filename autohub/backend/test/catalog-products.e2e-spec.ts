import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { as, bootApp, DEMO, login } from './helpers';

describe('Catalog, parts search and discovery', () => {
  let app: INestApplication;
  beforeAll(async () => { app = await bootApp(); });
  afterAll(async () => { await app.close(); });
  const http = () => app.getHttpServer();

  it('bootstrap is localised and supports ETag revalidation (304)', async () => {
    const hi = await request(http()).get('/v1/catalog/bootstrap').set('Accept-Language', 'hi').expect(200);
    const brakes = hi.body.categories.find((c: { slug: string }) => c.slug === 'brakes');
    expect(brakes.name).toBe('ब्रेक');
    expect(hi.body.makes.find((m: { slug: string }) => m.slug === 'maruti-suzuki').models.length).toBeGreaterThan(3);

    const etag = hi.headers.etag;
    expect(etag).toBeTruthy();
    await request(http()).get('/v1/catalog/bootstrap').set('Accept-Language', 'hi').set('If-None-Match', etag).expect(304);
  });

  it('fitment search shows only parts that fit the customer\'s car', async () => {
    const s = await login(app, DEMO.customer.phone, 'customer');
    const r = await as(app, s).get(`/v1/products?q=brake pad&vehicleId=${DEMO.swift}`).expect(200);
    const ids = r.body.data.map((p: { id: string }) => p.id);
    expect(ids).toContain(DEMO.brakePads);
    expect(ids).not.toContain(DEMO.cretaPads);
    expect(r.body.data[0]).toMatchObject({ fit: 'fits', pricePaise: 149900, mrpPaise: 180000, discountPercent: 16 });

    // universal-fit items (engine oil) appear for any car
    const oil = await as(app, s).get(`/v1/products?q=castrol&vehicleId=${DEMO.swift}`).expect(200);
    expect(oil.body.data[0].fit).toBe('universal');

    // someone else's vehicle id is not usable
    const other = await login(app, DEMO.glossOwner.phone, 'customer');
    await as(app, other).get(`/v1/products?vehicleId=${DEMO.swift}`).expect(404);
  });

  it('search handles prefixes, part numbers, filters, sorting and paging', async () => {
    const prefix = await request(http()).get('/v1/products?q=brak').expect(200);
    expect(prefix.body.data.length).toBe(2);

    const partNo = await request(http()).get('/v1/products?q=16510M68K00').expect(200);
    expect(partNo.body.data.map((p: { name: string }) => p.name)).toEqual(['Engine Oil Filter']);

    const cheap = await request(http()).get('/v1/products?maxPricePaise=50000&sort=price_asc').expect(200);
    const prices = cheap.body.data.map((p: { pricePaise: number }) => p.pricePaise);
    expect(prices).toEqual([...prices].sort((a, b) => a - b));
    expect(Math.max(...prices)).toBeLessThanOrEqual(50000);

    const p1 = await request(http()).get('/v1/products?limit=5&sort=newest').expect(200);
    expect(p1.body).toMatchObject({ hasMore: true });
    const p2 = await request(http()).get(`/v1/products?limit=5&sort=newest&cursor=${p1.body.nextCursor}`).expect(200);
    const overlap = p2.body.data.filter((x: { id: string }) => p1.body.data.some((y: { id: string }) => y.id === x.id));
    expect(overlap).toHaveLength(0);

    await request(http()).get('/v1/products?sort=cheapest').expect(400);
  });

  it('product detail includes fitment, stock and rating distribution', async () => {
    const r = await request(http()).get(`/v1/products/${DEMO.brakePads}`).expect(200);
    expect(r.body).toMatchObject({ sku: 'BP-SW-01', hsnCode: '87083000', stock: { inStock: true } });
    expect(r.body.fitments.map((f: { model: string }) => f.model)).toEqual(expect.arrayContaining(['Swift', 'Dzire']));
    expect(Object.keys(r.body.rating.distribution)).toHaveLength(5);
    await request(http()).get('/v1/products/00000000-0000-4000-8000-000000000000').expect(404);
  });

  it('nearby discovery filters by domain and sorts by distance', async () => {
    const r = await request(http()).get('/v1/vendors/nearby?lat=18.4893&lng=73.8203&radiusKm=25&domain=service').expect(200);
    const names = r.body.data.map((v: { businessName: string }) => v.businessName);
    expect(names).toEqual(['Shree Auto Parts & Service', 'Pitstop Car Care']);
    expect(r.body.data[0].distanceKm).toBeLessThan(r.body.data[1].distanceKm);

    const decor = await request(http()).get('/v1/vendors/nearby?lat=18.4893&lng=73.8203&radiusKm=25&domain=decor').expect(200);
    expect(decor.body.data.map((v: { slug: string }) => v.slug)).toEqual(['glossup-decor']);
  });

  it('vendor can add inventory; validation and SKU uniqueness enforced', async () => {
    const v = await login(app, DEMO.shreeOwner.phone, 'vendor', DEMO.shree);
    const c = as(app, v);
    const base = { subcategoryId: 0, sku: 'TEST-SKU-1', name: 'Rear Brake Shoe Set', partType: 'aftermarket', mrpPaise: 120000,
      pricePaise: 99900, gstRateBps: 1800, hsnCode: '87083000', stockQty: 5, status: 'draft' };
    const cat = await request(http()).get('/v1/catalog/categories?domain=parts').expect(200);
    base.subcategoryId = cat.body.find((x: { slug: string }) => x.slug === 'brakes').subcategories[0].id;

    const bad = await c.post('/v1/vendor/products', { ...base, pricePaise: 130000 }).expect(400);
    expect(bad.body.error.details.fields.pricePaise).toBeDefined();
    await c.post('/v1/vendor/products', { ...base, status: 'active' }).expect(400);   // no photos / fitment

    const ok = await c.post('/v1/vendor/products', base).expect(201);
    expect(ok.body).toMatchObject({ sku: 'TEST-SKU-1', status: 'draft' });
    const dup = await c.post('/v1/vendor/products', base).expect(409);
    expect(dup.body.error.message).toContain('TEST-SKU-1');

    const list = await c.get('/v1/vendor/products?q=Rear Brake').expect(200);
    expect(list.body.data).toHaveLength(1);
  });
});
