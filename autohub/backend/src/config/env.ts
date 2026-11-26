import { z } from 'zod';

const bool = z.enum(['true', 'false']).default('false').transform((v) => v === 'true');

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().default(3000),
    DATABASE_URL: z.string().min(1),
    REDIS_URL: z.string().optional().default(''),

    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().default(30),
    OTP_HMAC_SECRET: z.string().min(32, 'OTP_HMAC_SECRET must be at least 32 characters'),
    OTP_TTL_SECONDS: z.coerce.number().int().default(300),
    OTP_DEV_ECHO: bool,
    SMS_DRIVER: z.enum(['console', 'msg91']).default('console'),
    MSG91_AUTH_KEY: z.string().optional().default(''),
    MSG91_TEMPLATE_ID: z.string().optional().default(''),

    RAZORPAY_MODE: z.enum(['fake', 'live']).default('fake'),
    RAZORPAY_KEY_ID: z.string().min(1),
    RAZORPAY_KEY_SECRET: z.string().min(1),
    RAZORPAY_WEBHOOK_SECRET: z.string().min(1),

    GST_ON_COMMISSION_BPS: z.coerce.number().int().default(1800),
    TCS_BPS: z.coerce.number().int().default(100),
    TDS_194O_BPS: z.coerce.number().int().default(10),
    SERVICE_EARNING_HOLD_HOURS: z.coerce.number().int().default(48),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV !== 'production') return;
    const fail = (message: string) => ctx.addIssue({ code: 'custom', message });
    if (env.OTP_DEV_ECHO) fail('OTP_DEV_ECHO must be false in production');
    if (env.SMS_DRIVER !== 'msg91') fail('SMS_DRIVER must be msg91 in production');
    if (env.RAZORPAY_MODE !== 'live') fail('RAZORPAY_MODE must be live in production');
    if (!env.REDIS_URL) fail('REDIS_URL is required in production (shared rate limits)');
  });

export type Env = z.infer<typeof schema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  - ${i.path.join('.') || 'env'}: ${i.message}`);
    throw new Error(`Invalid environment configuration:\n${lines.join('\n')}`);
  }
  return parsed.data;
}

export const ENV = Symbol('ENV');
