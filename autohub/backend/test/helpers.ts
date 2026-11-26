import { INestApplication } from '@nestjs/common';
import { createHmac, randomUUID } from 'crypto';
import request from 'supertest';
import { createApp } from '../src/app';
import { loadEnv } from '../src/config/env';

export const DEMO = {
  customer: { phone: '+919000000001', id: 'd0000000-0000-4000-8000-000000000001' },
  shreeOwner: { phone: '+919000000002' },
  glossOwner: { phone: '+919000000004' },
  pitstopOwner: { phone: '+919000000005' },
  swift: 'd0000000-0000-4000-8000-0000000000a1',
  shree: 'd0000000-0000-4000-8000-0000000000b1',
  gloss: 'd0000000-0000-4000-8000-0000000000b2',
  pitstop: 'd0000000-0000-4000-8000-0000000000b3',
  svcBasic: 'd0000000-0000-4000-8000-000000000201',
  svcSuspension: 'd0000000-0000-4000-8000-000000000206',
  svcStereo: 'd0000000-0000-4000-8000-000000000223',
  brakePads: 'd0000000-0000-4000-8000-000000000101',
  cretaPads: 'd0000000-0000-4000-8000-000000000107',
};

export const testEnv = () => loadEnv({
  ...process.env,
  NODE_ENV: 'test',
  DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgres://postgres@127.0.0.1:5499/autohub_e2e?sslmode=disable',
  REDIS_URL: '',
  JWT_SECRET: 'test-jwt-secret-0123456789-0123456789-abcdef',
  OTP_HMAC_SECRET: 'test-otp-secret-0123456789-0123456789-abcdef',
  OTP_DEV_ECHO: 'true',
  SMS_DRIVER: 'console',
  RAZORPAY_MODE: 'fake',
  RAZORPAY_KEY_ID: 'rzp_fake_test',
  RAZORPAY_KEY_SECRET: 'fake_key_secret',
  RAZORPAY_WEBHOOK_SECRET: 'fake_webhook_secret',
});

export async function bootApp(): Promise<INestApplication> {
  const app = await createApp(testEnv());
  await app.init();
  return app;
}

export interface Session { accessToken: string; refreshToken: string; app: string; vendorId?: string }

export async function login(app: INestApplication, phone: string, clientApp: 'customer' | 'vendor' | 'admin', vendorId?: string): Promise<Session> {
  const http = app.getHttpServer();
  const r1 = await request(http).post('/v1/auth/otp/request').set('X-Client-App', clientApp).send({ phone }).expect(200);
  const r2 = await request(http).post('/v1/auth/otp/verify').set('X-Client-App', clientApp)
    .send({ otpRequestId: r1.body.otpRequestId, phone, code: r1.body.devCode, device: { platform: 'android' } }).expect(200);
  return { accessToken: r2.body.accessToken, refreshToken: r2.body.refreshToken, app: clientApp, vendorId };
}

/** Authenticated request builder. */
export function as(app: INestApplication, s: Session) {
  const http = app.getHttpServer();
  const wrap = (r: request.Test) => {
    r.set('Authorization', `Bearer ${s.accessToken}`).set('X-Client-App', s.app);
    if (s.vendorId) r.set('X-Vendor-Id', s.vendorId);
    return r;
  };
  return {
    get: (url: string) => wrap(request(http).get(url)),
    post: (url: string, body: object = {}, headers: Record<string, string> = {}) => {
      const r = wrap(request(http).post(url)).send(body);
      Object.entries(headers).forEach(([k, v]) => r.set(k, v));
      return r;
    },
  };
}

export const key = () => randomUUID();

/** Plays the role of Razorpay Checkout + the app: simulate a UPI success, then verify on the server. */
export async function pay(app: INestApplication, s: Session, razorpayOrderId: string, expectStatus = 200) {
  const c = as(app, s);
  const sim = await c.post('/v1/dev/payments/simulate', { razorpayOrderId }).expect(200);
  return c.post('/v1/payments/verify', sim.body).expect(expectStatus);
}

export function webhookSignature(body: string) {
  return createHmac('sha256', 'fake_webhook_secret').update(body).digest('hex');
}

/** First date with free slots at a vendor, at least a day out (so cancellation windows don't interfere). */
export async function firstFreeSlot(app: INestApplication, vendorId: string, minFree = 1) {
  const http = app.getHttpServer();
  for (let d = 1; d <= 10; d++) {
    const date = new Date(Date.now() + 330 * 60_000 + d * 86400_000).toISOString().slice(0, 10);
    const r = await request(http).get(`/v1/vendors/${vendorId}/slots?date=${date}`).expect(200);
    const slot = r.body.slots.find((s: { available: number }) => s.available >= minFree);
    if (slot) return slot as { id: string; startsAt: string; available: number };
  }
  throw new Error('no free slot found');
}
