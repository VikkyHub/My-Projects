# AutoHub

A marketplace connecting car owners with **spare-parts sellers**, **service centres** and **car decorators**, built for India (INR, UPI, GST, English, Hindi and Marathi).

| Part | Stack |
|---|---|
| Customer app, Vendor app | Flutter: Android (minSdk 24) + iOS 15+ |
| API + worker | NestJS, PostgreSQL 16 + PostGIS, Redis, BullMQ |
| Admin | React + Vite |
| Integrations | Razorpay (+ Route), MSG91 OTP, FCM/APNs, Google Maps, Cloudinary/S3 |

## Status
- [x] Phase 1: architecture, folder structure, PostgreSQL schema
- [x] Phase 2: REST API specification
- [x] **Phase 3: runnable code** — NestJS API (auth, catalog, parts search, bookings, Razorpay, vendor dashboard) and
      Flutter customer + partner apps (Android + iOS). Backend: 21 tests; Flutter: 12 tests incl. a live client↔server run.
- [ ] Phase 4: orders/cart/checkout, chat, admin panel, deployment guide, MVP vs Phase-2 scope

## ▶ Run it
See **[docs/04-run-and-test.md](docs/04-run-and-test.md)**: database → API → apps in about 10 minutes, with demo
shops and test logins. No Razorpay or SMS account needed: OTP codes and payments run in test mode.

## Docs
- [Architecture](docs/01-architecture.md)
- [Folder structure](docs/02-folder-structure.md)
- [REST API spec](docs/03-api-spec.md)
- [Run & test locally](docs/04-run-and-test.md)
- Schema: [`backend/db/migrations`](backend/db/migrations) (12 migrations, 57 tables), seeds in [`backend/db/seeds`](backend/db/seeds)
