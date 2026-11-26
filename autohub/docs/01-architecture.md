# AutoHub — Architecture (Phase 1)

> Working name **AutoHub**. Rename candidates: GaadiHub, Pitstop, CarSathi, Motorly.
> Status: **draft for approval**. API spec and code come after sign-off.

## 0. Decisions taken (defaults — change any of them)

| # | Topic | Decision |
|---|---|---|
| 1 | Team / timeline | 1–2 developers, MVP in ~12 weeks |
| 2 | Launch | One city first (Pune). Schema is multi-city from day one |
| 3 | Vehicles | Cars only. Two-wheelers later via the same make/model tables |
| 4 | Vendors | One vendor can be parts **and** service **and** decor (`vendors.business_domains[]`) |
| 5 | Service payments | Optional advance online, balance paid in-app after the approved estimate |
| 6 | Parts delivery | Vendor delivers locally (radius) in MVP; Shiprocket in Phase 2 |
| 7 | COD | Per-vendor toggle, capped (₹5,000) |
| 8 | Commission | Per domain (parts 8%, service 12%, decor 10%) → per category → per-vendor override |
| 9 | Fitment data | Our own make/model/variant master plus vendor-tagged fitment. Licensed dataset in Phase 2 |
| 10 | GST | Vendor is the seller of record; platform generates the invoice on their behalf and withholds **1% TCS (s.52)** |
| 11 | OTP | MSG91 (DLT-registered template); Firebase Phone Auth as fallback |
| 12 | Chat | Our own Socket.IO + Postgres |
| 13 | Apps | **Customer app** and **Vendor app**, both Flutter, **Android + iOS**, one monorepo. Admin is a React web app |
| 14 | Wallet | Closed-loop only (refunds/cashback, not withdrawable, no top-up), so no RBI PPI licence |

## 1. System diagram

```
┌──────────────────────────────┐   ┌──────────────────────────────┐   ┌────────────────────────┐
│  Customer app (Flutter)      │   │  Vendor app (Flutter)        │   │  Admin (React + Vite)  │
│  Android (minSdk 24) + iOS   │   │  Android (minSdk 24) + iOS   │   │  web, staff only       │
│  Riverpod · go_router · dio  │   │  same shared packages        │   │  TanStack Query        │
│  SQLite offline cache        │   │  SQLite offline cache        │   │                        │
└──────────────┬───────────────┘   └──────────────┬───────────────┘   └───────────┬────────────┘
               │ HTTPS (REST, JSON) + WSS (Socket.IO)                              │
               └───────────────────────┬──────────────────────────────────────────┘
                                       ▼
                       ┌───────────────────────────────┐
                       │  CDN / edge (Cloudflare)      │  TLS, WAF, rate limits, image CDN
                       └───────────────┬───────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│  API service — NestJS modular monolith (stateless, N replicas)                           │
│                                                                                          │
│  auth  users  vehicles  catalog  search  vendors  products  services  slots  bookings    │
│  cart  orders  payments  wallet  payouts  reviews  chat(gateway)  notifications          │
│  disputes  admin  analytics  media  invoices                                             │
│                                                                                          │
│  Cross-cutting: JwtGuard · RolesGuard · VendorMemberGuard · ValidationPipe (class-       │
│  validator) · ThrottlerGuard (Redis) · AuditInterceptor · idempotency middleware         │
└──────┬──────────────────┬────────────────────┬──────────────────────┬────────────────────┘
       │                  │                    │                      │ enqueue jobs
       ▼                  ▼                    ▼                      ▼
┌─────────────┐   ┌───────────────┐   ┌──────────────────┐   ┌──────────────────────────────┐
│ PostgreSQL  │   │ Redis         │   │ Cloudinary / S3  │   │ Worker — NestJS + BullMQ     │
│ 16 + PostGIS│   │ cache, OTP    │   │ public images:   │   │ • push / SMS / WhatsApp      │
│ pg_trgm     │   │ rate limits,  │   │   Cloudinary     │   │ • Razorpay webhook processor │
│ (primary;   │   │ BullMQ queues,│   │ private KYC docs:│   │ • payment reconciliation     │
│ read replica│   │ socket.io     │   │   S3 (signed URL)│   │ • slot generation (30 days)  │
│ later)      │   │ adapter       │   └──────────────────┘   │ • order expiry, earnings     │
└─────────────┘   └───────────────┘                          │   release, payout batches    │
                                                             │ • GST invoice PDFs           │
                                                             │ • nightly analytics roll-up  │
                                                             └──────────────────────────────┘
External services:
  Razorpay (Payments + Route for vendor split settlement + webhooks)   MSG91 (OTP SMS, DLT)
  Firebase Cloud Messaging (→ APNs on iOS)   Google Maps Platform (Maps SDK, Places, Geocoding)
  Sentry (crash + API errors)   Firebase Analytics / PostHog (product analytics)
```

### Why a modular monolith (not microservices)
At 10k users a single deployable is cheaper, faster to build and easier to debug. Each NestJS module owns its tables and talks to other modules only through their service interfaces, so any module (search, chat, notifications) can be split out later without a rewrite.

### Why REST, not GraphQL
HTTP caching and ETags help the offline cache, Razorpay webhooks are REST anyway, and it is simpler to secure per endpoint. The only screens that would benefit from GraphQL are the home feeds, and a few purpose-built "aggregate" endpoints cover those.

## 2. Mobile (Flutter): Android + iOS

| Concern | Choice | Why |
|---|---|---|
| Min OS | Android 7.0 (API 24), **iOS 15** | iOS 15 is the floor for the current Firebase iOS SDK and covers ~98% of active iPhones |
| State | Riverpod 2 (code-gen) | Testable, no BuildContext coupling |
| Routing | go_router | Deep links from push notifications (`/orders/:id`) |
| HTTP | dio + interceptors | JWT refresh, retry, `Accept-Language`, ETag |
| Offline | **SQLite response cache** (sqflite) | Every listing GET is cached by URL with its ETag: shown instantly, revalidated with `If-None-Match`, served from cache when offline (300 entries, LRU). Move to Drift when relational offline data (e.g. a draft cart) is needed |
| Images | cached_network_image + Cloudinary URL transforms (`f_auto,q_auto,w_<px>`) | Low-end phones get small WebP/AVIF |
| Maps | google_maps_flutter (lite mode on Android list views) | Lite mode is far lighter on low-RAM devices |
| Payments | razorpay_flutter | UPI intent/collect, cards, netbanking, wallets on both platforms |
| Push | firebase_messaging (APNs key uploaded to Firebase for iOS) | One pipeline for both platforms |
| i18n | flutter gen-l10n, ARB files `en`, `hi`, `mr` | Catalog names come from the API (`name_i18n`) |
| Crash | sentry_flutter | |

**Low-end Android budget:** APK < 25 MB per ABI (`--split-per-abi`), cold start < 3 s on 2 GB RAM, list pages paginated at 20, images ≤ 400 px wide in lists, no blur or shadow effects in scrolling lists, `--obfuscate --split-debug-info`.

**iOS-specific requirements:**
- **No Apple In-App Purchase needed.** Parts, services and decor are physical goods or real-world services (App Store Guideline 3.1.3(e) / 3.1.5), so Razorpay is allowed.
- **In-app account deletion** is mandatory (5.1.1(v)) → `users.deleted_at` plus a delete flow.
- Sign in with Apple is **not** required, because we offer only phone OTP and no third-party social login.
- Permission strings (`NSLocationWhenInUseUsageDescription`, camera, photos), a Privacy Manifest, and App Privacy "nutrition labels".
- iOS builds need macOS: use **Codemagic** or GitHub Actions macOS runners if there's no Mac on the team.

## 3. Key flows

### 3.1 OTP login
```
App ──POST /auth/otp/request {phone}──▶ API ── rate limit (Redis: 1/30s, 5/hour per phone, 20/hour per IP)
                                        ├─ store HMAC(code) in otp_requests (expires 5 min)
                                        └─ MSG91 send (DLT template)
App ──POST /auth/otp/verify {phone, code, device}──▶ API
     ├─ constant-time compare; attempts++ (max 5 → lock)
     ├─ upsert user, create user_sessions row (refresh token hash)
     └─▶ { accessToken (JWT, 15 min), refreshToken (opaque, 30 days, rotated on every use) }
```

### 3.2 Parts checkout (multi-vendor cart → one payment)
```
1. POST /checkout {cart, address, mode, Idempotency-Key}
   → in one transaction: lock products (SELECT … FOR UPDATE), reserve stock,
     create order_group + one order per vendor (status pending_payment),
     freeze prices, tax, commission, TCS, and create a Razorpay order.
2. App opens Razorpay checkout (UPI / card / wallet / netbanking).
3. App → POST /payments/verify {razorpay_order_id, payment_id, signature}
   → server verifies the HMAC signature, fetches the payment from Razorpay, checks amount + currency,
     marks captured, orders → placed, notifies vendors.
4. The webhook payment.captured does the same idempotently (covers app killed mid-payment).
5. Sweeper: pending_payment orders older than 30 min → payment_failed, stock released.
```

### 3.3 Service booking with estimate
```
requested → (vendor accepts) confirmed → vehicle_received → estimate_shared ⇄ (customer approves)
→ in_progress → ready → (balance paid) completed
Side exits: rejected · cancelled · no_show
Slot capacity is guaranteed by the DB: vendor_slots.booked_count ≤ capacity.
```

### 3.4 Money movement
```
Customer pays ──▶ Razorpay ──(Route transfer, on_hold until return window closes)──▶ Vendor bank
                     │
                     └─ platform keeps commission + TCS
Ledger mirror: vendor_ledger_entries (earning +, refund −, payout −); available balance = SUM where available_at ≤ now()
```
If Route activation is delayed, the fallback is to collect into the platform account and pay out with RazorpayX. The schema supports both (`payouts.razorpay_transfer_id`).

## 4. Data model overview

57 tables across 11 migrations (full DDL in `backend/db/migrations`).

```
users ─┬─< vehicles >── vehicle_models >── vehicle_makes        vehicle_variants ─< (vehicles, fitments)
       ├─< addresses
       ├─< user_sessions, device_tokens, otp_requests(by phone)
       ├── wallets ─< wallet_transactions
       ├── carts ─< cart_items >── products
       └─< vendor_members >── vendors ─┬─< vendor_documents
                                       ├─< vendor_bank_accounts ─< payouts
                                       ├─< products ─┬─< product_images
                                       │             ├─< product_fitments
                                       │             └─< inventory_movements
                                       ├─< services ─< service_images
                                       ├─< vendor_working_hours, vendor_holidays, vendor_slots
                                       ├─< vendor_ledger_entries, vendor_daily_stats
                                       └─< chat_conversations ─< chat_messages

categories(domain) ─< subcategories ─< (products, services)        commission_rules, brands

order_groups ─< orders ─┬─< order_items ─< return_requests
   │                    └─< order_status_history
   └─< payments ─< refunds                  payment_webhook_events (inbox)

bookings ─┬─< booking_services        reviews ─< review_media   (order XOR booking: verified only)
          ├─< booking_estimates ─< booking_estimate_items
          ├─< booking_attachments     disputes ─< dispute_messages ─> refunds
          └─< booking_status_history  notifications · audit_logs · favorite_vendors
```

### Schema conventions
- **Money:** `bigint` paise everywhere (`*_paise`). Never floats.
- **GST:** rates in basis points (`1800` = 18%), HSN for goods and SAC for services, stored on every line. Rate slabs are not hard-coded, because the 2025 GST rationalisation already changed them once.
- **IDs:** UUID for entities exposed in URLs. `bigint identity` for high-volume, append-only tables (messages, ledgers, history), which doubles as a pagination cursor.
- **Snapshots:** order items, addresses and booking services copy name, price and tax at purchase time, so vendor edits never change past invoices.
- **Soft delete:** `deleted_at` on user-facing entities. Partial unique indexes (`WHERE deleted_at IS NULL`) allow, for example, a deleted user's phone number to sign up again.
- **State lives in the DB:** `CHECK` constraints enforce price ≤ MRP, reserved ≤ stock, order total math, payout math, slot capacity, one pending estimate, verified-purchase reviews, one in-flight payout, one open dispute per order, ledger signs, and the GSTIN/PAN/IFSC/pincode/registration-number formats.
- **Status history tables** feed the live tracking timelines.
- **i18n:** catalog names in `name_i18n jsonb` (`en` required, `hi`/`mr` optional, client falls back to `en`).

## 5. Scaling path: 10k → 1M users

| Stage | Users | Changes |
|---|---|---|
| **MVP** | ≤ 10k | 1 API + 1 worker on Render/Railway, managed Postgres (PostGIS), managed Redis. Postgres full-text + trigram search. ~₹8–15k/month |
| **Growth** | 10k–100k | 2–4 API replicas, PgBouncer, a Postgres read replica for search/analytics, Cloudflare caching of the catalog GETs, move to **AWS Mumbai (ap-south-1)** for latency |
| **Scale** | 100k–1M | Search → Typesense/Meilisearch/OpenSearch (fed by an outbox table); monthly partitions for `chat_messages`, `notifications` and `audit_logs`; the chat gateway as its own service; analytics → ClickHouse/BigQuery via CDC; per-city vendor sharding is **not** needed even at 1M users |

What makes this possible later without a rewrite: stateless API, all IDs non-sequential, no cross-module SQL joins outside each module's repository layer for the parts that will be split (search, chat, notifications), and an append-only ledger instead of mutable balances for vendors.

## 6. Environments

| Env | Backend | DB | Apps |
|---|---|---|---|
| local | docker-compose (Postgres+PostGIS, Redis) | seed data | emulator / simulator, Razorpay **test** keys |
| staging | Render/Railway (Singapore region) | separate DB | Firebase App Distribution / TestFlight |
| prod | Render/Railway → AWS Mumbai at Growth stage | PITR backups on | Play Store + App Store |
