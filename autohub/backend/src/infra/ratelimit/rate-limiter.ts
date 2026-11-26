import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import Redis from 'ioredis';
import { ENV, Env } from '../../config/env';
import { Errors } from '../../common/errors';

export interface RateLimiter {
  /** Counts one hit for `key` in a fixed window. Returns the hit count and seconds until the window resets. */
  hit(key: string, windowSeconds: number): Promise<{ count: number; ttl: number }>;
  peek(key: string): Promise<number>;
  reset(key: string): Promise<void>;
  close(): Promise<void>;
}

export class RedisRateLimiter implements RateLimiter {
  constructor(private readonly redis: Redis) {}
  async hit(key: string, windowSeconds: number) {
    const k = `rl:${key}`;
    const [[, count], [, ttl]] = (await this.redis
      .multi().incr(k).ttl(k).exec()) as [[null, number], [null, number]];
    if (ttl < 0) await this.redis.expire(k, windowSeconds);
    return { count, ttl: ttl < 0 ? windowSeconds : ttl };
  }
  async peek(key: string) { return Number((await this.redis.get(`rl:${key}`)) ?? 0); }
  async reset(key: string) { await this.redis.del(`rl:${key}`); }
  async close() { await this.redis.quit(); }
}

/** Single-process fallback for local dev and tests. */
export class MemoryRateLimiter implements RateLimiter {
  private readonly buckets = new Map<string, { count: number; resetAt: number }>();
  async hit(key: string, windowSeconds: number) {
    const now = Date.now();
    let b = this.buckets.get(key);
    if (!b || b.resetAt <= now) {
      b = { count: 0, resetAt: now + windowSeconds * 1000 };
      this.buckets.set(key, b);
    }
    b.count += 1;
    return { count: b.count, ttl: Math.ceil((b.resetAt - now) / 1000) };
  }
  async peek(key: string) {
    const b = this.buckets.get(key);
    return b && b.resetAt > Date.now() ? b.count : 0;
  }
  async reset(key: string) { this.buckets.delete(key); }
  async close() {}
}

export const RATE_LIMITER = Symbol('RATE_LIMITER');
export const InjectRateLimiter = () => Inject(RATE_LIMITER);

/** Throws 429 when `key` exceeds `limit` hits per `windowSeconds`. */
export async function enforceLimit(rl: RateLimiter, key: string, limit: number, windowSeconds: number) {
  const { count, ttl } = await rl.hit(key, windowSeconds);
  if (count > limit) throw Errors.rateLimited(ttl);
}

@Global()
@Module({
  providers: [{
    provide: RATE_LIMITER,
    inject: [ENV],
    useFactory: (env: Env): RateLimiter =>
      env.REDIS_URL ? new RedisRateLimiter(new Redis(env.REDIS_URL, { maxRetriesPerRequest: 2 })) : new MemoryRateLimiter(),
  }],
  exports: [RATE_LIMITER],
})
export class RateLimitModule implements OnApplicationShutdown {
  constructor(@InjectRateLimiter() private readonly rl: RateLimiter) {}
  async onApplicationShutdown() { await this.rl.close(); }
}
