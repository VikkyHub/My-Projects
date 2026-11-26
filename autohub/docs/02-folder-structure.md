# Folder structure

One Git monorepo: Flutter apps, NestJS backend and React admin in one place.

```
autohub/
├── docs/                         # architecture, API spec, runbooks
├── infra/
│   ├── docker-compose.yml        # Postgres 16 + PostGIS, Redis (local dev)
│   └── render.yaml               # (Phase 2 deliverable) infra-as-code for Render
├── backend/                      # NestJS API + worker (same codebase, two entrypoints)
├── admin/                        # React admin dashboard
├── mobile/                       # Flutter workspace (customer + vendor apps)
└── .github/workflows/            # CI: lint, test, migrations check, builds
```

## Backend (NestJS)

```
backend/
├── db/
│   ├── migrations/               # plain SQL, dbmate format (-- migrate:up / -- migrate:down)
│   ├── seeds/                    # reference data (categories en/hi/mr, makes/models, brands)
│   └── tests/                    # schema smoke tests (constraints, triggers, geo + fitment queries)
├── src/
│   ├── main.ts                   # HTTP + Socket.IO entrypoint
│   ├── worker.ts                 # BullMQ worker entrypoint (no HTTP)
│   ├── app.module.ts
│   ├── config/                   # typed env config (zod-validated at boot)
│   ├── common/
│   │   ├── guards/               # jwt-auth, roles, vendor-member, throttler
│   │   ├── decorators/           # @CurrentUser, @Roles, @VendorScope, @Idempotent
│   │   ├── interceptors/         # audit-log, response envelope, request-id
│   │   ├── filters/              # error → { code, message, details }
│   │   ├── pipes/                # validation
│   │   ├── money/                # paise helpers, GST split, commission calc
│   │   └── pagination/           # cursor pagination helpers
│   ├── infra/
│   │   ├── db/                   # Kysely instance, generated DB types, transaction helper
│   │   ├── redis/
│   │   ├── queue/                # BullMQ queue definitions
│   │   ├── razorpay/             # SDK wrapper + signature verification
│   │   ├── sms/                  # MSG91 client (+ console driver for local)
│   │   ├── fcm/
│   │   ├── storage/              # Cloudinary (public) + S3 (private KYC docs)
│   │   └── maps/                 # geocoding with Redis cache
│   └── modules/
│       ├── auth/                 # otp request/verify, refresh, logout
│       │   ├── auth.controller.ts
│       │   ├── auth.service.ts
│       │   ├── otp.service.ts
│       │   ├── token.service.ts
│       │   ├── dto/
│       │   └── auth.service.spec.ts
│       ├── users/  vehicles/  addresses/
│       ├── catalog/              # categories, subcategories, brands, vehicle master (cached)
│       ├── vendors/              # onboarding, documents, profile, discovery (nearby)
│       ├── products/             # vendor inventory CRUD, customer listing/search, fitment
│       ├── services/             # service & decor catalog
│       ├── slots/                # working hours, holidays, slot generation
│       ├── bookings/             # booking lifecycle, estimates, attachments
│       ├── cart/  checkout/  orders/  returns/
│       ├── payments/             # create order, verify, webhooks, refunds
│       ├── wallet/  payouts/  ledger/
│       ├── reviews/  chat/  notifications/
│       ├── disputes/
│       ├── analytics/            # vendor dashboard stats, admin KPIs
│       ├── invoices/             # GST invoice PDF generation
│       └── admin/                # admin-only controllers (approvals, moderation, settings)
├── test/                         # e2e tests (supertest against a test DB)
├── Dockerfile
├── package.json
└── .env.example
```

Data access uses **Kysely** (type-safe SQL builder) with types generated from the live schema (`kysely-codegen`). Migrations stay as plain SQL because the schema relies on partial indexes, PostGIS, generated columns and cross-column CHECK constraints, which ORMs model poorly.

## Mobile (Flutter workspace, Android + iOS)

As built in Phase 3 (Dart pub workspace: one `flutter pub get` at `mobile/` resolves all three packages):

```
mobile/
├── pubspec.yaml                      # workspace root
├── packages/autohub_core/            # shared by both apps
│   └── lib/
│       ├── autohub_core.dart         # exports + bootstrapCore()
│       ├── l10n/app_{en,hi,mr}.arb   # translations → l10n/gen (flutter gen-l10n)
│       └── src/
│           ├── api_client.dart       # dio, error envelope, single-flight token refresh, ETag/offline getCached()
│           ├── response_cache.dart   # SQLite (sqflite) GET cache, LRU 300
│           ├── token_store.dart      # Keychain / Keystore via flutter_secure_storage
│           ├── session.dart          # OTP login state, vendor shop switcher, language
│           ├── login_screen.dart     # phone → OTP screen used by both apps
│           ├── payments.dart         # Razorpay Checkout + server verification (test sheet in fake mode)
│           ├── money.dart            # paise ↔ ₹ with Indian digit grouping
│           ├── ui.dart               # theme, status chips, error/offline widgets
│           └── testing.dart          # FakeAdapter for widget/unit tests
├── apps/customer_app/                # bundle id app.autohub.customer
│   ├── android/ ios/
│   └── lib/
│       ├── main.dart  app.dart       # go_router: login redirect + bottom tabs
│       └── features/
│           ├── parts/                # fitment-aware search list, product detail
│           ├── services/             # nearby service centres / decorators
│           ├── booking/              # book flow, live booking page (estimate approve, pay), my bookings
│           └── account/
└── apps/vendor_app/                  # "AutoHub Partner", bundle id app.autohub.partner
    ├── android/ ios/
    └── lib/features/
        ├── dashboard/                # KPIs, action items, today's schedule, 7-day revenue bars
        └── bookings/                 # job card: confirm → check-in → estimate → start → ready
```

Phase 4 adds: cart/checkout/orders, inventory editor, chat, push (FCM), maps view, vendor registration.

## Admin (React)

```
admin/
├── src/
│   ├── main.tsx  App.tsx  routes.tsx
│   ├── api/                      # fetch client, TanStack Query hooks
│   ├── auth/                     # OTP login + admin_role check, idle timeout
│   ├── pages/
│   │   ├── dashboard/            # GMV, orders, active users, repeat rate, top vendors
│   │   ├── vendors/              # approval queue, document viewer, vendor detail
│   │   ├── catalog/              # categories, subcategories, brands, vehicle master
│   │   ├── orders/  bookings/  payments/  refunds/
│   │   ├── payouts/              # approval queue, batch export
│   │   ├── disputes/             # queue with SLA, thread, resolve + refund
│   │   ├── moderation/           # reviews + photos
│   │   ├── commission/
│   │   └── audit-log/
│   └── components/
├── package.json
└── vite.config.ts
```
