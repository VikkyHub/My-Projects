import { INestApplication } from '@nestjs/common';
import { Pool } from 'pg';
import request from 'supertest';
import { as, bootApp, DEMO, firstFreeSlot, key, login, pay, Session, testEnv, webhookSignature } from './helpers';

describe('Booking flow with estimate, Razorpay payments and settlement', () => {
  let app: INestApplication;
  let db: Pool;
  let customer: Session;
  let shree: Session;
  beforeAll(async () => {
    app = await bootApp();
    db = new Pool({ connectionString: testEnv().DATABASE_URL });
    customer = await login(app, DEMO.customer.phone, 'customer');
    shree = await login(app, DEMO.shreeOwner.phone, 'vendor', DEMO.shree);
  });
  afterAll(async () => { await db.end(); await app.close(); });

  it('runs the full job: book → advance → confirm → check-in → estimate → approve → ready → pay balance → completed', async () => {
    const c = as(app, customer);
    const v = as(app, shree);
    const slot = await firstFreeSlot(app, DEMO.shree);
    const idem = key();

    // 1. Customer books a fixed-price service + an inspection-priced one, with a ₹200 advance.
    const created = await c.post('/v1/bookings', {
      vendorId: DEMO.shree, vehicleId: DEMO.swift, serviceIds: [DEMO.svcBasic, DEMO.svcSuspension], slotId: slot.id,
      customerNotes: 'Knocking noise from front left',
    }, { 'Idempotency-Key': idem }).expect(201);
    expect(created.body).toMatchObject({ status: 'requested', payments: { quotedTotalPaise: 299900, advancePaise: 20000 } });
    expect(created.body.bookingNumber).toMatch(/^BKG-\d{6}-\d{6}$/);
    expect(created.body.payment.razorpay).toMatchObject({ amountPaise: 20000, currency: 'INR', keyId: 'rzp_fake_test' });
    const id = created.body.id;

    // Same Idempotency-Key → same booking, no second seat taken.
    const replay = await c.post('/v1/bookings', {
      vendorId: DEMO.shree, vehicleId: DEMO.swift, serviceIds: [DEMO.svcBasic, DEMO.svcSuspension], slotId: slot.id,
    }, { 'Idempotency-Key': idem }).expect(201);
    expect(replay.body.id).toBe(id);
    const after = await request(app.getHttpServer()).get(`/v1/vendors/${DEMO.shree}/slots?date=${new Date(new Date(slot.startsAt).getTime() + 330 * 60_000).toISOString().slice(0, 10)}`);
    expect(after.body.slots.find((s: { id: string }) => s.id === slot.id).available).toBe(slot.available - 1);

    // 2. Pay the advance (Razorpay fake mode → signature verified server-side).
    const adv = await pay(app, customer, created.body.payment.razorpay.orderId);
    expect(adv.body).toMatchObject({ status: 'captured', booking: { paymentState: 'partially_paid', amountPaidPaise: 20000 } });

    // 3. Vendor side. Phone masked until confirmed.
    const pending = await v.get(`/v1/vendor/bookings/${id}`).expect(200);
    expect(pending.body.customer.phone).toContain('••');
    await v.post(`/v1/vendor/bookings/${id}/start`).expect(409);           // can't skip ahead
    const confirmed = await v.post(`/v1/vendor/bookings/${id}/confirm`).expect(200);
    expect(confirmed.body.customer.phone).toBe(DEMO.customer.phone);
    await v.post(`/v1/vendor/bookings/${id}/check-in`, { odometerKm: 42310 }).expect(200);

    // Inspection-priced service → vendor must send an estimate before starting.
    const noEst = await v.post(`/v1/vendor/bookings/${id}/start`).expect(422);
    expect(noEst.body.error.code).toBe('ESTIMATE_REQUIRED');

    // 4. Estimate (tax-exclusive lines; server computes tax and totals).
    const est = await v.post(`/v1/vendor/bookings/${id}/estimates`, {
      items: [
        { kind: 'service', description: 'Basic Service', quantity: 1, unitPricePaise: 254100, gstRateBps: 1800, hsnSacCode: '998714' },
        { kind: 'part', description: 'Front-left stabiliser link', quantity: 1, unitPricePaise: 95000, gstRateBps: 1800 },
        { kind: 'labour', description: 'Link replacement labour', quantity: 1, unitPricePaise: 50900, gstRateBps: 1800 },
        { kind: 'service', description: 'Wheel alignment (recommended)', quantity: 1, unitPricePaise: 59100, gstRateBps: 1800, isOptional: true },
      ],
      vendorNote: 'Stabiliser link worn out',
    }).expect(201);
    expect(est.body).toMatchObject({ version: 1, subtotalPaise: 459100, taxPaise: 82638, totalPaise: 541738 });

    const view = await c.get(`/v1/bookings/${id}`).expect(200);
    expect(view.body.status).toBe('estimate_shared');
    expect(view.body.estimate.ifOptionalDeclined).toEqual({ subtotalPaise: 400000, taxPaise: 72000, totalPaise: 472000 });
    const required = view.body.estimate.items.find((i: { isOptional: boolean }) => !i.isOptional);
    const optional = view.body.estimate.items.find((i: { isOptional: boolean }) => i.isOptional);

    // Can't decline a mandatory line.
    await c.post(`/v1/bookings/${id}/estimates/${est.body.id}/approve`, { declinedItemIds: [required.id] }).expect(400);

    // 5. Customer approves, declining the optional alignment.
    const approved = await c.post(`/v1/bookings/${id}/estimates/${est.body.id}/approve`, { declinedItemIds: [optional.id] }).expect(200);
    expect(approved.body).toMatchObject({ status: 'in_progress', payments: { finalTotalPaise: 472000, balanceDuePaise: 452000 } });

    // 6. Work done → balance payment.
    await v.post(`/v1/vendor/bookings/${id}/ready`).expect(200);
    const balance = await c.post(`/v1/bookings/${id}/payments`, { purpose: 'booking_balance' }).expect(201);
    expect(balance.body.razorpay.amountPaise).toBe(452000);
    const paid = await pay(app, customer, balance.body.razorpay.orderId);
    expect(paid.body.booking).toMatchObject({ status: 'completed', paymentState: 'paid', amountPaidPaise: 472000 });

    // 7. Settlement frozen on the booking: 12% commission, 18% GST on it, 1% TCS + 0.1% TDS on taxable ₹4,000.
    const done = await v.get(`/v1/vendor/bookings/${id}`).expect(200);
    expect(done.body.settlement).toEqual({
      commissionPaise: 56640, commissionGstPaise: 10195, tcsPaise: 4000, tdsPaise: 400, vendorPayoutPaise: 400765,
    });
    const ledger = await db.query(`SELECT type, amount_paise, available_at > now() AS on_hold FROM vendor_ledger_entries WHERE booking_id = $1`, [id]);
    expect(ledger.rows).toEqual([{ type: 'booking_earning', amount_paise: 400765, on_hold: true }]);
    expect(done.body.timeline.map((t: { status: string }) => t.status)).toEqual(
      ['requested', 'confirmed', 'vehicle_received', 'estimate_shared', 'in_progress', 'ready', 'completed']);

    // Verifying the same payment again is a harmless no-op.
    const again = await c.post('/v1/dev/payments/simulate', { razorpayOrderId: balance.body.razorpay.orderId }).expect(200);
    await c.post('/v1/payments/verify', again.body).expect(200);
    const count = await db.query(`SELECT count(*)::int AS n FROM vendor_ledger_entries WHERE booking_id = $1`, [id]);
    expect(count.rows[0].n).toBe(1);
  });

  it('never double-books the last seat (capacity 1, two customers at once)', async () => {
    const slot = await firstFreeSlot(app, DEMO.gloss);
    expect(slot.available).toBe(1);
    const other = await login(app, '+919111100002', 'customer');
    const swift = (await db.query(`SELECT id, make_id FROM vehicle_models WHERE slug = 'swift'`)).rows[0];
    const otherVehicle = await as(app, other).post('/v1/me/vehicles', {
      makeId: swift.make_id, modelId: swift.id,
      manufactureYear: 2020, fuelType: 'petrol', registrationNumber: 'mh-12-xy-9999',
    }).expect(201);
    expect(otherVehicle.body.registrationNumber).toBe('MH12XY9999');

    const body = (vehicleId: string) => ({ vendorId: DEMO.gloss, vehicleId, serviceIds: [DEMO.svcStereo], slotId: slot.id });
    const results = await Promise.all([
      as(app, customer).post('/v1/bookings', body(DEMO.swift), { 'Idempotency-Key': key() }),
      as(app, other).post('/v1/bookings', body(otherVehicle.body.id), { 'Idempotency-Key': key() }),
    ]);
    const statuses = results.map((r) => r.status).sort();
    expect(statuses).toEqual([201, 409]);
    const loser = results.find((r) => r.status === 409)!;
    expect(loser.body.error.code).toBe('SLOT_UNAVAILABLE');
    expect(loser.body.error.details.nextSlots.length).toBeGreaterThan(0);
  });

  it('cancellation releases the seat and queues a refund of the advance', async () => {
    const c = as(app, customer);
    const slot = await firstFreeSlot(app, DEMO.shree);
    const b = await c.post('/v1/bookings', { vendorId: DEMO.shree, vehicleId: DEMO.swift, serviceIds: [DEMO.svcBasic], slotId: slot.id },
      { 'Idempotency-Key': key() }).expect(201);
    await pay(app, customer, b.body.payment.razorpay.orderId);
    const cancelled = await c.post(`/v1/bookings/${b.body.id}/cancel`, { reason: 'Plans changed' }).expect(200);
    expect(cancelled.body.status).toBe('cancelled');
    const seat = await db.query(`SELECT booked_count FROM vendor_slots WHERE id = $1`, [slot.id]);
    expect(seat.rows[0].booked_count).toBe(3 - slot.available);   // back to what it was before this booking
    const refund = await db.query(`SELECT amount_paise, destination, status FROM refunds WHERE booking_id = $1`, [b.body.id]);
    expect(refund.rows).toEqual([{ amount_paise: 20000, destination: 'source', status: 'pending' }]);
    await c.post(`/v1/bookings/${b.body.id}/cancel`).expect(409);
  });

  it('rejects forged payment signatures and other users\' payments', async () => {
    const c = as(app, customer);
    const slot = await firstFreeSlot(app, DEMO.shree);
    const b = await c.post('/v1/bookings', { vendorId: DEMO.shree, vehicleId: DEMO.swift, serviceIds: [DEMO.svcBasic], slotId: slot.id },
      { 'Idempotency-Key': key() }).expect(201);
    const orderId = b.body.payment.razorpay.orderId;
    const sim = await c.post('/v1/dev/payments/simulate', { razorpayOrderId: orderId }).expect(200);

    const forged = await c.post('/v1/payments/verify', { ...sim.body, razorpaySignature: 'a'.repeat(64) }).expect(422);
    expect(forged.body.error.code).toBe('PAYMENT_VERIFICATION_FAILED');

    const stranger = await login(app, '+919111100003', 'customer');
    await as(app, stranger).post('/v1/payments/verify', sim.body).expect(422);

    await c.post('/v1/payments/verify', sim.body).expect(200);
  });

  it('webhooks: bad signature rejected, valid event captures once, duplicates ignored', async () => {
    const c = as(app, customer);
    const slot = await firstFreeSlot(app, DEMO.shree);
    const b = await c.post('/v1/bookings', { vendorId: DEMO.shree, vehicleId: DEMO.swift, serviceIds: [DEMO.svcBasic], slotId: slot.id },
      { 'Idempotency-Key': key() }).expect(201);
    const orderId = b.body.payment.razorpay.orderId;
    const event = JSON.stringify({
      event: 'payment.captured',
      payload: { payment: { entity: { id: 'pay_webhook01', order_id: orderId, amount: 20000, currency: 'INR', status: 'captured', method: 'upi' } } },
    });
    const http = app.getHttpServer();
    await request(http).post('/v1/webhooks/razorpay').set('content-type', 'application/json')
      .set('x-razorpay-signature', 'b'.repeat(64)).send(event).expect(422);

    const send = () => request(http).post('/v1/webhooks/razorpay').set('content-type', 'application/json')
      .set('x-razorpay-signature', webhookSignature(event)).set('x-razorpay-event-id', 'evt_test_1').send(event);
    expect((await send().expect(200)).body).toEqual({ ok: true });
    expect((await send().expect(200)).body).toEqual({ ok: true, duplicate: true });

    const view = await c.get(`/v1/bookings/${b.body.id}`).expect(200);
    expect(view.body.payments).toMatchObject({ amountPaidPaise: 20000, paymentState: 'partially_paid' });
  });

  it('vendor dashboard reflects bookings, earnings and the 7-day chart', async () => {
    const r = await as(app, shree).get('/v1/vendor/dashboard').expect(200);
    expect(r.body.vendor).toMatchObject({ businessName: 'Shree Auto Parts & Service', status: 'approved' });
    expect(r.body.last7Days).toHaveLength(7);
    expect(r.body.earnings.availablePaise).toBeGreaterThan(0);          // demo history past the 48 h hold
    expect(r.body.earnings.onHoldPaise).toBeGreaterThanOrEqual(400765);  // the job completed above
    expect(r.body.actionItems.some((a: { type: string }) => a.type === 'low_stock')).toBe(true);

    // other shops can't see Shree's bookings
    const pit = await login(app, DEMO.pitstopOwner.phone, 'vendor', DEMO.pitstop);
    const list = await as(app, shree).get('/v1/vendor/bookings').expect(200);
    await as(app, pit).get(`/v1/vendor/bookings/${list.body.data[0].id}`).expect(404);
  });
});
