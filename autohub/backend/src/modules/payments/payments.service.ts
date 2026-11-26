import { Injectable, Logger } from '@nestjs/common';
import { Errors } from '../../common/errors';
import { Database, InjectDb, Tx } from '../../infra/db/database';
import type { PaymentPurpose } from '../../infra/db/db.types';
import { RazorpayPayment, RazorpayService } from '../../infra/razorpay/razorpay.service';

/** Runs inside the capture transaction, exactly once per captured payment. */
export type CaptureHandler = (tx: Tx, payment: { id: string; bookingId: string | null; orderGroupId: string | null; amountPaise: number; purpose: PaymentPurpose }) => Promise<void>;

export interface CheckoutPayload {
  paymentId: string;
  razorpay: { keyId: string; orderId: string; amountPaise: number; currency: 'INR'; name: string; description: string; prefill: { contact: string; name: string | null } };
}

@Injectable()
export class PaymentsService {
  private readonly log = new Logger('Payments');
  private readonly handlers = new Map<'booking' | 'order', CaptureHandler>();

  constructor(@InjectDb() private readonly db: Database, private readonly razorpay: RazorpayService) {}

  registerCaptureHandler(kind: 'booking' | 'order', handler: CaptureHandler) {
    this.handlers.set(kind, handler);
  }

  /** Creates (or reuses) a Razorpay order for a booking advance or balance. */
  async createForBooking(userId: string, bookingId: string, purpose: 'booking_advance' | 'booking_balance'): Promise<CheckoutPayload> {
    const b = await this.db.selectFrom('bookings as b').innerJoin('users as u', 'u.id', 'b.customerId')
      .select(['b.id', 'b.bookingNumber', 'b.status', 'b.advancePaise', 'b.amountPaidPaise', 'b.finalTotalPaise', 'u.phone', 'u.fullName'])
      .where('b.id', '=', bookingId).where('b.customerId', '=', userId).executeTakeFirst();
    if (!b) throw Errors.notFound('Booking');

    let amount: number;
    if (purpose === 'booking_advance') {
      if (!['requested', 'confirmed'].includes(b.status)) throw Errors.invalidTransition(b.status, 'pay the advance', ['requested', 'confirmed']);
      amount = b.advancePaise - b.amountPaidPaise;
    } else {
      if (b.status !== 'ready') throw Errors.invalidTransition(b.status, 'pay the balance', ['ready']);
      amount = (b.finalTotalPaise ?? 0) - b.amountPaidPaise;
    }
    if (amount < 100) throw Errors.rule('NOTHING_TO_PAY', 'Nothing is due right now.');

    // Retrying "Pay" must not create a second Razorpay order for the same amount.
    const open = await this.db.selectFrom('payments').select(['id', 'razorpayOrderId', 'amountPaise'])
      .where('bookingId', '=', b.id).where('purpose', '=', purpose).where('status', '=', 'created')
      .where('amountPaise', '=', amount).where('createdAt', '>', new Date(Date.now() - 20 * 60_000)).executeTakeFirst();
    const row = open ?? await (async () => {
      const order = await this.razorpay.createOrder(amount, b.bookingNumber, { bookingId: b.id, purpose });
      return this.db.insertInto('payments').values({
        userId, purpose, bookingId: b.id, amountPaise: amount, razorpayOrderId: order.id,
      }).returning(['id', 'razorpayOrderId', 'amountPaise']).executeTakeFirstOrThrow();
    })();

    return {
      paymentId: row.id,
      razorpay: {
        keyId: this.razorpay.keyId, orderId: row.razorpayOrderId, amountPaise: row.amountPaise, currency: 'INR',
        name: 'AutoHub', description: `${purpose === 'booking_advance' ? 'Advance' : 'Payment'} for ${b.bookingNumber}`,
        prefill: { contact: b.phone, name: b.fullName },
      },
    };
  }

  /**
   * Called by the app after Razorpay Checkout succeeds. Never trusts the client:
   * 1) HMAC signature, 2) the payment as Razorpay reports it (order, amount, currency, status), 3) idempotent capture.
   */
  async verify(userId: string, input: { razorpayOrderId: string; razorpayPaymentId: string; razorpaySignature: string }) {
    const fail = () => Errors.rule('PAYMENT_VERIFICATION_FAILED', 'We could not verify this payment. If money was debited it will be refunded automatically.');
    const p = await this.db.selectFrom('payments').selectAll()
      .where('razorpayOrderId', '=', input.razorpayOrderId).where('userId', '=', userId).executeTakeFirst();
    if (!p) throw fail();
    if (!this.razorpay.verifyPaymentSignature(input.razorpayOrderId, input.razorpayPaymentId, input.razorpaySignature)) {
      this.log.warn(`Bad checkout signature for ${input.razorpayOrderId}`);
      throw fail();
    }
    if (p.status === 'captured') return this.result(p.id);

    let remote: RazorpayPayment;
    try {
      remote = await this.razorpay.fetchPayment(input.razorpayPaymentId);
    } catch (e) {
      this.log.error(`fetchPayment failed: ${(e as Error).message}`);
      throw fail();
    }
    if (remote.order_id !== p.razorpayOrderId || remote.amount !== p.amountPaise || remote.currency !== 'INR') {
      this.log.error(`Payment mismatch for ${p.id}: ${JSON.stringify({ order: remote.order_id, amount: remote.amount })}`);
      throw fail();
    }
    if (remote.status === 'captured') {
      await this.capture(p.razorpayOrderId, remote);
      return this.result(p.id);
    }
    if (remote.status === 'authorized') {
      // Auto-capture is on; Razorpay will capture shortly and the webhook will finish the job.
      await this.db.updateTable('payments').set({ status: 'authorized', razorpayPaymentId: remote.id })
        .where('id', '=', p.id).where('status', '=', 'created').execute();
      return { ...(await this.result(p.id)), status: 'authorized' as const };
    }
    await this.markFailed(p.razorpayOrderId, remote);
    throw fail();
  }

  async status(userId: string, paymentId: string) {
    const p = await this.db.selectFrom('payments').select('id').where('id', '=', paymentId).where('userId', '=', userId).executeTakeFirst();
    if (!p) throw Errors.notFound('Payment');
    return this.result(p.id);
  }

  /** Razorpay webhook. Dedupes on event id; reprocesses an event whose earlier processing failed. */
  async handleWebhook(rawBody: Buffer | undefined, signature: string | undefined, eventId: string | undefined) {
    if (!rawBody || !signature || !this.razorpay.verifyWebhookSignature(rawBody, signature)) {
      throw Errors.rule('INVALID_SIGNATURE', 'Webhook signature invalid.');
    }
    const event = JSON.parse(rawBody.toString('utf8')) as { event: string; payload: { payment?: { entity: RazorpayPayment } } };
    const id = eventId ?? `${event.event}:${event.payload.payment?.entity.id ?? 'unknown'}`;
    const inserted = await this.db.insertInto('paymentWebhookEvents')
      .values({ eventId: id, eventType: event.event, payload: JSON.stringify(event) })
      .onConflict((oc) => oc.columns(['provider', 'eventId']).doNothing()).returning(['id', 'processedAt']).executeTakeFirst();
    const row = inserted ?? await this.db.selectFrom('paymentWebhookEvents').select(['id', 'processedAt'])
      .where('provider', '=', 'razorpay').where('eventId', '=', id).executeTakeFirstOrThrow();
    if (!inserted && row.processedAt) return { ok: true, duplicate: true };

    try {
      const entity = event.payload.payment?.entity;
      if (entity && (event.event === 'payment.captured' || event.event === 'order.paid')) {
        const p = await this.db.selectFrom('payments').select(['amountPaise']).where('razorpayOrderId', '=', entity.order_id).executeTakeFirst();
        if (p && p.amountPaise === entity.amount && entity.currency === 'INR') await this.capture(entity.order_id, entity);
        else this.log.warn(`Webhook for unknown/mismatched order ${entity.order_id}`);
      } else if (entity && event.event === 'payment.failed') {
        await this.markFailed(entity.order_id, entity);
      }
      await this.db.updateTable('paymentWebhookEvents').set({ processedAt: new Date(), error: null }).where('id', '=', row.id).execute();
    } catch (e) {
      await this.db.updateTable('paymentWebhookEvents').set({ error: (e as Error).message.slice(0, 500) }).where('id', '=', row.id).execute();
      throw e;   // 500 → Razorpay retries, and the retry reprocesses because processed_at is still NULL
    }
    return { ok: true };
  }

  /** Fake mode only — stands in for the Razorpay Checkout sheet during local testing. */
  simulate(razorpayOrderId: string) {
    if (!this.razorpay.isFake) throw Errors.notFound();
    const r = this.razorpay.simulateSuccessfulPayment(razorpayOrderId);
    if (!r) throw Errors.notFound('Razorpay order');
    return r;
  }

  private async capture(razorpayOrderId: string, remote: RazorpayPayment) {
    await this.db.transaction().execute(async (tx) => {
      const p = await tx.selectFrom('payments').selectAll().where('razorpayOrderId', '=', razorpayOrderId).forUpdate().executeTakeFirstOrThrow();
      if (p.status === 'captured' || p.status === 'refunded' || p.status === 'partially_refunded') return;   // idempotent
      await tx.updateTable('payments').set({
        status: 'captured', razorpayPaymentId: remote.id, method: remote.method ?? null, capturedAt: new Date(),
        methodDetail: JSON.stringify({ vpa: remote.vpa, bank: remote.bank, wallet: remote.wallet, cardNetwork: remote.card?.network, last4: remote.card?.last4 }),
      }).where('id', '=', p.id).execute();
      const handler = this.handlers.get(p.bookingId ? 'booking' : 'order');
      if (!handler) throw new Error(`No capture handler for payment ${p.id}`);
      await handler(tx, p);
    });
  }

  private async markFailed(razorpayOrderId: string, remote: RazorpayPayment) {
    await this.db.updateTable('payments').set({
      status: 'failed', failureCode: remote.error_code ?? null, failureReason: remote.error_description ?? null,
    }).where('razorpayOrderId', '=', razorpayOrderId).where('status', 'in', ['created', 'authorized']).execute();
  }

  private async result(paymentId: string) {
    const p = await this.db.selectFrom('payments').select(['id', 'status', 'purpose', 'amountPaise', 'bookingId', 'orderGroupId', 'method'])
      .where('id', '=', paymentId).executeTakeFirstOrThrow();
    const booking = p.bookingId
      ? await this.db.selectFrom('bookings').select(['id', 'status', 'paymentState', 'amountPaidPaise']).where('id', '=', p.bookingId).executeTakeFirst()
      : null;
    return { paymentId: p.id, status: p.status, purpose: p.purpose, amountPaise: p.amountPaise, method: p.method, booking };
  }
}
