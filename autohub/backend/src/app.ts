import 'reflect-metadata';
import { Controller, Get, INestApplication, Module, ValidationPipe } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, NestFactory } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { randomUUID } from 'crypto';
import { ENV, Env, loadEnv } from './config/env';
import { AuthGuard, Public } from './common/auth';
import { AllExceptionsFilter, Errors } from './common/errors';
import { DatabaseModule } from './infra/db/database';
import { RateLimitModule } from './infra/ratelimit/rate-limiter';
import { RazorpayModule } from './infra/razorpay/razorpay.service';
import { SmsModule } from './infra/sms/sms.service';
import { AuthModule } from './modules/auth/auth.controller';
import { BookingsModule } from './modules/bookings/bookings.module';
import { CatalogModule } from './modules/catalog/catalog.module';
import { MeModule } from './modules/me/me.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { ProductsModule } from './modules/products/products.module';
import { SlotsModule } from './modules/slots/slots.module';
import { VehiclesModule } from './modules/vehicles/vehicles.module';
import { VendorDashboardModule } from './modules/vendor-dashboard/vendor-dashboard.module';
import { VendorsModule } from './modules/vendors/vendors.module';

@Controller()
class HealthController {
  @Public() @Get('health') health() { return { ok: true }; }
}

export function buildAppModule(env: Env) {
  @Module({
    imports: [
      { module: class EnvModule {}, global: true, providers: [{ provide: ENV, useValue: env }], exports: [ENV] },
      JwtModule.register({ global: true, secret: env.JWT_SECRET }),
      DatabaseModule, RateLimitModule, SmsModule, RazorpayModule,
      AuthModule, MeModule, VehiclesModule, CatalogModule, ProductsModule, VendorsModule,
      PaymentsModule, BookingsModule, VendorDashboardModule, SlotsModule,
    ],
    controllers: [HealthController],
    providers: [
      { provide: APP_GUARD, useClass: AuthGuard },
      { provide: APP_FILTER, useClass: AllExceptionsFilter },
    ],
  })
  class AppModule {}
  return AppModule;
}

export async function createApp(env: Env = loadEnv()): Promise<INestApplication> {
  const app = await NestFactory.create<NestExpressApplication>(buildAppModule(env), {
    rawBody: true,                                   // webhook signatures are computed over raw bytes
    logger: env.NODE_ENV === 'test' ? ['error'] : ['log', 'warn', 'error'],
  });
  app.set('trust proxy', 1);                         // real client IP behind Render/Railway/Cloudflare (rate limits)
  app.use((req: { id?: string; headers: Record<string, string | undefined> }, res: { setHeader: (k: string, v: string) => void }, next: () => void) => {
    req.id = req.headers['x-request-id']?.slice(0, 64) || randomUUID();
    res.setHeader('X-Request-Id', req.id);
    next();
  });
  app.enableCors({ origin: env.NODE_ENV === 'production' ? [/\.autohub\.in$/] : true });
  app.setGlobalPrefix('v1', { exclude: ['health'] });
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true, forbidNonWhitelisted: true, transform: true,
    exceptionFactory: (errors) => {
      const fields: Record<string, string> = {};
      const walk = (errs: typeof errors, prefix = '') => errs.forEach((e) => {
        const key = prefix + e.property;
        if (e.constraints) fields[key] = Object.values(e.constraints)[0];
        if (e.children?.length) walk(e.children, `${key}.`);
      });
      walk(errors);
      return Errors.validation(fields);
    },
  }));

  if (env.NODE_ENV !== 'production') {
    const doc = SwaggerModule.createDocument(app, new DocumentBuilder()
      .setTitle('AutoHub API').setVersion('0.1.0')
      .setDescription('Send header **X-Client-App** (customer | vendor | admin). Vendor routes also need **X-Vendor-Id**.')
      .addBearerAuth().addGlobalParameters({ name: 'X-Client-App', in: 'header', required: false, schema: { type: 'string', enum: ['customer', 'vendor', 'admin'] } })
      .build());
    SwaggerModule.setup('docs', app, doc, { swaggerOptions: { persistAuthorization: true } });
  }
  return app;
}
