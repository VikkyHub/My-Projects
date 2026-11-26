import { Global, Inject, Injectable, Module } from '@nestjs/common';
import { createHmac, randomBytes, timingSafeEqual } from 'crypto';
import { ENV, Env } from '../../config/env';

export interface RazorpayOrder { id: string; amount: number; currency: string; receipt: string; status: string }
export interface RazorpayPayment {
  id: string; order_id: string; amount: number; currency: string;
  status: 'created' | 'authorized' | 'captured' | 'refunded' | 'failed';
  method?: string; vpa?: string; bank?: string; wallet?: string;
  card?: { network?: string; last4?: string };
  error_code?: string; error_description?: string;
}

export function safeEqualHex(a: string, b: string): boolean {
  const ab = Buffer.from(a, 'utf8');
  const bb = Buffer.from(b, 'utf8');
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

/**
 * Razorpay REST wrapper. `RAZORPAY_MODE=fake` keeps everything local so the full payment flow
 * can be exercised without an account; signatures are still real HMACs over the same inputs.
 */
@Injectable()
export class RazorpayService {
  private readonly fakeOrders = new Map<string, RazorpayOrder>();
  private readonly fakePayments = new Map<string, RazorpayPayment>();

  constructor(@Inject(ENV) private readonly env: Env) {}

  get keyId() { return this.env.RAZORPAY_KEY_ID; }
  get isFake() { return this.env.RAZORPAY_MODE === 'fake'; }

  async createOrder(amountPaise: number, receipt: string, notes: Record<string, string>): Promise<RazorpayOrder> {
    if (this.isFake) {
      const order = { id: `order_fake${randomBytes(7).toString('hex')}`, amount: amountPaise, currency: 'INR', receipt, status: 'created' };
      this.fakeOrders.set(order.id, order);
      return order;
    }
    // payment_capture=1: authorised payments are captured automatically.
    return this.call<RazorpayOrder>('POST', '/v1/orders', { amount: amountPaise, currency: 'INR', receipt, notes, payment_capture: 1 });
  }

  async fetchPayment(paymentId: string): Promise<RazorpayPayment> {
    if (this.isFake) {
      const p = this.fakePayments.get(paymentId);
      if (!p) throw new Error('Unknown fake payment');
      return p;
    }
    return this.call<RazorpayPayment>('GET', `/v1/payments/${encodeURIComponent(paymentId)}`);
  }

  /** Checkout signature: HMAC_SHA256(order_id + "|" + payment_id, key_secret). */
  verifyPaymentSignature(orderId: string, paymentId: string, signature: string): boolean {
    const expected = createHmac('sha256', this.env.RAZORPAY_KEY_SECRET).update(`${orderId}|${paymentId}`).digest('hex');
    return safeEqualHex(expected, signature);
  }

  /** Webhook signature: HMAC_SHA256(raw request body, webhook_secret). */
  verifyWebhookSignature(rawBody: Buffer, signature: string): boolean {
    const expected = createHmac('sha256', this.env.RAZORPAY_WEBHOOK_SECRET).update(rawBody).digest('hex');
    return safeEqualHex(expected, signature);
  }

  /** Fake mode only: what Razorpay Checkout would hand the app after a successful UPI payment. */
  simulateSuccessfulPayment(orderId: string, method = 'upi') {
    if (!this.isFake) throw new Error('simulateSuccessfulPayment is only available in fake mode');
    const order = this.fakeOrders.get(orderId);
    if (!order) return null;
    const payment: RazorpayPayment = {
      id: `pay_fake${randomBytes(7).toString('hex')}`, order_id: orderId, amount: order.amount, currency: 'INR',
      status: 'captured', method, vpa: method === 'upi' ? 'success@razorpay' : undefined,
    };
    this.fakePayments.set(payment.id, payment);
    const signature = createHmac('sha256', this.env.RAZORPAY_KEY_SECRET).update(`${orderId}|${payment.id}`).digest('hex');
    return { razorpayOrderId: orderId, razorpayPaymentId: payment.id, razorpaySignature: signature };
  }

  private async call<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
    const auth = Buffer.from(`${this.env.RAZORPAY_KEY_ID}:${this.env.RAZORPAY_KEY_SECRET}`).toString('base64');
    const res = await fetch(`https://api.razorpay.com${path}`, {
      method,
      headers: { authorization: `Basic ${auth}`, 'content-type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(10_000),
    });
    const json = (await res.json()) as T & { error?: { description?: string } };
    if (!res.ok) throw new Error(`Razorpay ${method} ${path} failed: ${res.status} ${json.error?.description ?? ''}`);
    return json;
  }
}

@Global()
@Module({ providers: [RazorpayService], exports: [RazorpayService] })
export class RazorpayModule {}
