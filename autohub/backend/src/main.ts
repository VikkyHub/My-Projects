import { Logger } from '@nestjs/common';
import { createApp } from './app';
import { loadEnv } from './config/env';

async function main() {
  try {
    process.loadEnvFile?.('.env');           // Node ≥ 20.12; real env vars win over the file
  } catch { /* no .env file — fine in containers */ }
  const env = loadEnv();
  const app = await createApp(env);
  app.enableShutdownHooks();
  await app.listen(env.PORT, '0.0.0.0');
  const log = new Logger('AutoHub');
  log.log(`API listening on http://localhost:${env.PORT}/v1  (Swagger UI: http://localhost:${env.PORT}/docs)`);
  if (env.RAZORPAY_MODE === 'fake') log.warn('Razorpay is in FAKE mode — use POST /v1/dev/payments/simulate to pay.');
  if (env.OTP_DEV_ECHO) log.warn('OTP_DEV_ECHO is on — OTP codes are returned in API responses.');
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
