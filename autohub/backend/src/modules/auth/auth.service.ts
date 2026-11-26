import { Inject, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'crypto';
import { ENV, Env } from '../../config/env';
import { AccessTokenClaims } from '../../common/auth';
import { Errors } from '../../common/errors';
import { Database, InjectDb } from '../../infra/db/database';
import type { ClientApp, DevicePlatform } from '../../infra/db/db.types';
import { enforceLimit, InjectRateLimiter, RateLimiter } from '../../infra/ratelimit/rate-limiter';
import { SmsService } from '../../infra/sms/sms.service';

export interface DeviceInfo { deviceId?: string; platform?: DevicePlatform; appVersion?: string }

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AuthService {
  constructor(
    @InjectDb() private readonly db: Database,
    @Inject(ENV) private readonly env: Env,
    @InjectRateLimiter() private readonly rl: RateLimiter,
    private readonly jwt: JwtService,
    private readonly sms: SmsService,
  ) {}

  // ---------- OTP ----------

  async requestOtp(phone: string, ip: string | undefined) {
    if (await this.rl.peek(`otp-block:${phone}`) >= 3) throw Errors.rateLimited(24 * 3600);
    await enforceLimit(this.rl, `otp-req-30s:${phone}`, 1, 30);
    await enforceLimit(this.rl, `otp-req-1h:${phone}`, 5, 3600);
    if (ip) await enforceLimit(this.rl, `otp-req-ip:${ip}`, 20, 3600);

    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const row = await this.db.insertInto('otpRequests').values({
      phone, purpose: 'login', codeHash: 'pending',
      expiresAt: new Date(Date.now() + this.env.OTP_TTL_SECONDS * 1000), requestIp: ip ?? null,
    }).returning('id').executeTakeFirstOrThrow();
    // The hash binds the code to this request id, so a code can't be replayed against another request.
    await this.db.updateTable('otpRequests').set({ codeHash: this.hashOtp(row.id, code) }).where('id', '=', row.id).execute();

    const providerRef = await this.sms.sendOtp(phone, code);
    if (providerRef) await this.db.updateTable('otpRequests').set({ providerRef }).where('id', '=', row.id).execute();

    return {
      otpRequestId: row.id,
      expiresInSeconds: this.env.OTP_TTL_SECONDS,
      resendAfterSeconds: 30,
      ...(this.env.OTP_DEV_ECHO && this.env.NODE_ENV !== 'production' ? { devCode: code } : {}),
    };
  }

  async verifyOtp(input: { otpRequestId: string; phone: string; code: string; app: ClientApp; device: DeviceInfo; ip?: string; userAgent?: string }) {
    await enforceLimit(this.rl, `otp-verify:${input.phone}`, 10, 600);

    const otp = await this.db.selectFrom('otpRequests').selectAll()
      .where('id', '=', input.otpRequestId).where('phone', '=', input.phone).executeTakeFirst();
    if (!otp || otp.consumedAt) throw Errors.rule('OTP_INVALID', 'Incorrect or used code. Request a new one.', { attemptsLeft: 0 });
    if (otp.expiresAt.getTime() < Date.now()) throw Errors.rule('OTP_EXPIRED', 'Code expired. Request a new one.');
    if (otp.attempts >= otp.maxAttempts) throw Errors.rule('OTP_LOCKED', 'Too many wrong attempts. Request a new code.');

    const expected = Buffer.from(otp.codeHash, 'hex');
    const actual = Buffer.from(this.hashOtp(otp.id, input.code), 'hex');
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      const attempts = otp.attempts + 1;
      await this.db.updateTable('otpRequests').set({ attempts }).where('id', '=', otp.id).execute();
      if (attempts >= otp.maxAttempts) {
        await this.rl.hit(`otp-block:${input.phone}`, 24 * 3600);   // 3 locked OTPs in 24 h => phone blocked for 24 h
        throw Errors.rule('OTP_LOCKED', 'Too many wrong attempts. Request a new code.');
      }
      throw Errors.rule('OTP_INVALID', 'Incorrect code.', { attemptsLeft: otp.maxAttempts - attempts });
    }

    return this.db.transaction().execute(async (tx) => {
      const consumed = await tx.updateTable('otpRequests').set({ consumedAt: new Date() })
        .where('id', '=', otp.id).where('consumedAt', 'is', null).returning('id').executeTakeFirst();
      if (!consumed) throw Errors.rule('OTP_INVALID', 'Code already used.', { attemptsLeft: 0 });

      let user = await tx.selectFrom('users').selectAll().where('phone', '=', input.phone).where('deletedAt', 'is', null).executeTakeFirst();
      const isNewUser = !user;
      if (!user) {
        user = await tx.insertInto('users').values({ phone: input.phone, phoneVerifiedAt: new Date() }).returningAll().executeTakeFirstOrThrow();
        await tx.insertInto('wallets').values({ userId: user.id }).execute();
      }
      if (user.status !== 'active') throw Errors.forbidden('This account is suspended. Contact support.');
      if (input.app === 'admin' && !user.adminRole) throw Errors.forbidden();
      await tx.updateTable('users').set({ lastLoginAt: new Date() }).where('id', '=', user.id).execute();

      const tokens = await this.createSession(tx, user.id, input.app, input.device, input.ip, input.userAgent);
      const vendorMemberships = input.app === 'vendor'
        ? await tx.selectFrom('vendorMembers as m').innerJoin('vendors as v', 'v.id', 'm.vendorId')
            .select(['v.id as vendorId', 'v.businessName', 'm.role', 'v.status'])
            .where('m.userId', '=', user.id).where('v.deletedAt', 'is', null).execute()
        : [];
      return {
        ...tokens,
        isNewUser,
        user: { id: user.id, phone: user.phone, fullName: user.fullName, preferredLanguage: user.preferredLanguage, adminRole: user.adminRole },
        vendorMemberships,
      };
    });
  }

  // ---------- tokens ----------

  async refresh(refreshToken: string) {
    const hash = sha256(refreshToken);
    const reused = await this.db.selectFrom('userSessions').select(['userId', 'revokedAt', 'replacedBy'])
      .where('refreshTokenHash', '=', hash).executeTakeFirst();
    if (reused?.revokedAt && reused.replacedBy) {
      // A rotated token was used again: someone else has a copy. Kill every session of this user.
      // (Committed on its own — doing this inside the transaction below would be rolled back by the throw.)
      await this.logoutAll(reused.userId);
      throw Errors.unauthenticated();
    }
    return this.db.transaction().execute(async (tx) => {
      const s = await tx.selectFrom('userSessions').selectAll().where('refreshTokenHash', '=', hash).forUpdate().executeTakeFirst();
      if (!s || s.revokedAt) throw Errors.unauthenticated();
      if (s.expiresAt.getTime() < Date.now()) throw Errors.unauthenticated();
      const user = await tx.selectFrom('users').select(['status']).where('id', '=', s.userId).executeTakeFirstOrThrow();
      if (user.status !== 'active') throw Errors.unauthenticated();

      const next = await this.createSession(tx, s.userId, s.app,
        { deviceId: s.deviceId ?? undefined, platform: s.platform ?? undefined, appVersion: s.appVersion ?? undefined },
        s.ip ?? undefined, s.userAgent ?? undefined);
      await tx.updateTable('userSessions').set({ revokedAt: new Date(), replacedBy: next.sessionId }).where('id', '=', s.id).execute();
      return next;
    });
  }

  async logout(sessionId: string) {
    await this.db.updateTable('userSessions').set({ revokedAt: new Date() }).where('id', '=', sessionId).where('revokedAt', 'is', null).execute();
  }

  async logoutAll(userId: string) {
    await this.db.updateTable('userSessions').set({ revokedAt: new Date() }).where('userId', '=', userId).where('revokedAt', 'is', null).execute();
  }

  private async createSession(tx: Database, userId: string, app: ClientApp, device: DeviceInfo, ip?: string, userAgent?: string) {
    const refreshToken = `rt_${randomBytes(32).toString('base64url')}`;
    const session = await tx.insertInto('userSessions').values({
      userId, app, refreshTokenHash: sha256(refreshToken),
      deviceId: device.deviceId ?? null, platform: device.platform ?? null, appVersion: device.appVersion ?? null,
      ip: ip ?? null, userAgent: userAgent?.slice(0, 300) ?? null,
      expiresAt: new Date(Date.now() + this.env.REFRESH_TOKEN_TTL_DAYS * 86400_000),
    }).returning('id').executeTakeFirstOrThrow();
    const claims: AccessTokenClaims = { sub: userId, app, sid: session.id };
    const accessToken = await this.jwt.signAsync(claims, { expiresIn: this.env.ACCESS_TOKEN_TTL_SECONDS, algorithm: 'HS256' });
    return { accessToken, accessTokenExpiresIn: this.env.ACCESS_TOKEN_TTL_SECONDS, refreshToken, sessionId: session.id };
  }

  private hashOtp(otpRequestId: string, code: string) {
    return createHmac('sha256', this.env.OTP_HMAC_SECRET).update(`${otpRequestId}:${code}`).digest('hex');
  }
}
