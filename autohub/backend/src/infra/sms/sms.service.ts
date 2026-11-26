import { Global, Inject, Injectable, Logger, Module } from '@nestjs/common';
import { ENV, Env } from '../../config/env';

@Injectable()
export class SmsService {
  private readonly log = new Logger('SMS');
  constructor(@Inject(ENV) private readonly env: Env) {}

  /** Sends the login OTP. In console mode the code is only logged (never in production — see env.ts). */
  async sendOtp(phone: string, code: string): Promise<string | null> {
    if (this.env.SMS_DRIVER === 'console') {
      this.log.warn(`[console SMS] OTP for ${phone}: ${code}`);
      return null;
    }
    // MSG91 OTP API with a DLT-approved template. Variables: ##OTP##
    const res = await fetch('https://control.msg91.com/api/v5/otp?' + new URLSearchParams({
      template_id: this.env.MSG91_TEMPLATE_ID,
      mobile: phone.replace('+', ''),
      otp: code,
    }), { method: 'POST', headers: { authkey: this.env.MSG91_AUTH_KEY, 'content-type': 'application/json' } });
    const body = (await res.json().catch(() => ({}))) as { type?: string; request_id?: string; message?: string };
    if (!res.ok || body.type === 'error') {
      this.log.error(`MSG91 send failed: ${res.status} ${body.message ?? ''}`);
      throw new Error('SMS provider error');
    }
    return body.request_id ?? null;
  }
}

@Global()
@Module({ providers: [SmsService], exports: [SmsService] })
export class SmsModule {}
