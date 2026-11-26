import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { as, bootApp, DEMO, login } from './helpers';

describe('Auth (OTP + JWT + refresh rotation + RBAC)', () => {
  let app: INestApplication;
  beforeAll(async () => { app = await bootApp(); });
  afterAll(async () => { await app.close(); });

  const http = () => app.getHttpServer();
  const newPhone = '+919111100001';

  it('signs up a new user with OTP; wrong codes count down and are rejected', async () => {
    const r1 = await request(http()).post('/v1/auth/otp/request').set('X-Client-App', 'customer').send({ phone: newPhone }).expect(200);
    expect(r1.body).toMatchObject({ expiresInSeconds: 300, resendAfterSeconds: 30 });
    expect(r1.body.devCode).toMatch(/^\d{6}$/);

    const wrong = r1.body.devCode === '000000' ? '111111' : '000000';
    const bad = await request(http()).post('/v1/auth/otp/verify').set('X-Client-App', 'customer')
      .send({ otpRequestId: r1.body.otpRequestId, phone: newPhone, code: wrong }).expect(422);
    expect(bad.body.error).toMatchObject({ code: 'OTP_INVALID', details: { attemptsLeft: 4 } });

    const ok = await request(http()).post('/v1/auth/otp/verify').set('X-Client-App', 'customer')
      .send({ otpRequestId: r1.body.otpRequestId, phone: newPhone, code: r1.body.devCode }).expect(200);
    expect(ok.body.isNewUser).toBe(true);
    expect(ok.body.accessToken).toBeTruthy();

    // A code works exactly once.
    await request(http()).post('/v1/auth/otp/verify').set('X-Client-App', 'customer')
      .send({ otpRequestId: r1.body.otpRequestId, phone: newPhone, code: r1.body.devCode }).expect(422);

    const me = await request(http()).get('/v1/me').set('Authorization', `Bearer ${ok.body.accessToken}`).set('X-Client-App', 'customer').expect(200);
    expect(me.body).toMatchObject({ phone: newPhone, walletBalancePaise: 0 });
  });

  it('rate-limits OTP requests per phone (1 per 30 s) with Retry-After', async () => {
    const r = await request(http()).post('/v1/auth/otp/request').set('X-Client-App', 'customer').send({ phone: newPhone }).expect(429);
    expect(r.body.error.code).toBe('RATE_LIMITED');
    expect(Number(r.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('rejects malformed phone numbers', async () => {
    const r = await request(http()).post('/v1/auth/otp/request').set('X-Client-App', 'customer').send({ phone: '9876543210' }).expect(400);
    expect(r.body.error.code).toBe('VALIDATION_FAILED');
    expect(r.body.error.details.fields.phone).toBeDefined();
  });

  it('rotates refresh tokens and revokes everything when a rotated token is reused', async () => {
    const s = await login(app, DEMO.customer.phone, 'customer');
    const r1 = await request(http()).post('/v1/auth/refresh').send({ refreshToken: s.refreshToken }).expect(200);
    expect(r1.body.refreshToken).not.toBe(s.refreshToken);

    // Old token replayed (e.g. stolen) → 401, and the legitimate new session is killed too.
    await request(http()).post('/v1/auth/refresh').send({ refreshToken: s.refreshToken }).expect(401);
    await request(http()).post('/v1/auth/refresh').send({ refreshToken: r1.body.refreshToken }).expect(401);
    await request(http()).get('/v1/me').set('Authorization', `Bearer ${r1.body.accessToken}`).set('X-Client-App', 'customer').expect(401);
  });

  it('logout makes the access token unusable immediately', async () => {
    const s = await login(app, DEMO.pitstopOwner.phone, 'customer');
    await as(app, s).post('/v1/auth/logout').expect(204);
    await as(app, s).get('/v1/me').expect(401);
  });

  it('enforces app binding and vendor membership', async () => {
    const customer = await login(app, DEMO.shreeOwner.phone, 'customer');
    // customer-app token on a vendor route
    await as(app, { ...customer, vendorId: DEMO.gloss }).get('/v1/vendor/dashboard').expect(403);
    // token presented as a different app
    await request(http()).get('/v1/me').set('Authorization', `Bearer ${customer.accessToken}`).set('X-Client-App', 'vendor').expect(401);

    const vendor = await login(app, DEMO.glossOwner.phone, 'vendor', DEMO.gloss);
    await as(app, vendor).get('/v1/vendor/dashboard').expect(200);
    // member of GlossUp, not of Shree
    await as(app, { ...vendor, vendorId: DEMO.shree }).get('/v1/vendor/dashboard').expect(403);
    // missing header
    await as(app, { ...vendor, vendorId: undefined }).get('/v1/vendor/dashboard').expect(403);
  });
});
