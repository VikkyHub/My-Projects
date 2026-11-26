# AutoHub REST API v1

Status: **draft for approval**. Field names map 1:1 to the schema in `backend/db/migrations` (DB `snake_case` ↔ API `camelCase`).
In Phase 3 the NestJS code will generate an OpenAPI 3.1 document from this contract (served at `/docs`). The Dart client in `mobile/packages/api_client` will be generated from that document, so the apps and the API can't drift apart.

---

## 1. Conventions

### 1.1 Base URLs
| Env | URL |
|---|---|
| local | `http://localhost:3000/v1` (Android emulator: `http://10.0.2.2:3000/v1`) |
| staging | `https://api-staging.autohub.in/v1` |
| prod | `https://api.autohub.in/v1` |

WebSocket (Socket.IO): same host, path `/ws`.

### 1.2 Headers
| Header | When | Notes |
|---|---|---|
| `Authorization: Bearer <accessToken>` | every authenticated call | JWT, 15-minute lifetime |
| `X-Client-App: customer \| vendor \| admin` | every call | Tokens are bound to an app; a customer-app token is rejected on `/vendor/*` |
| `X-App-Version: 1.4.0+42` | mobile | Server can answer `426 UPGRADE_REQUIRED` for builds below the minimum |
| `X-Vendor-Id: <uuid>` | every `/vendor/*` call | A user can belong to several shops; the guard checks `vendor_members` |
| `Accept-Language: en \| hi \| mr` | optional | Picks `name_i18n` values and error message language |
| `Idempotency-Key: <uuid v4>` | **required** on `POST /checkout`, `POST /bookings`, `POST /vendor/payouts`, `POST /admin/refunds` | Same key + same body → same response for 24 h. Same key + different body → `409 IDEMPOTENCY_KEY_REUSED` |
| `If-None-Match: "<etag>"` | catalog / listing GETs | `304 Not Modified` saves data on slow networks and feeds the offline cache |

### 1.3 Data formats
- **Money:** integer **paise**, field suffix `Paise` (`"pricePaise": 149900` = ₹1,499.00). Clients format; the API never sends formatted strings.
- **GST:** basis points, suffix `Bps` (`"gstRateBps": 1800` = 18%). Item prices are **GST-inclusive** (Indian MRP convention), and tax is broken out separately for invoices.
- **Time:** ISO-8601 in UTC (`2026-12-01T04:30:00Z`). Slot lists also carry `localDate`/`localTime` in IST for display.
- **IDs:** UUID strings. Human-facing references (`orderNumber`, `bookingNumber`, `disputeNumber`) are separate fields.
- **Phone:** E.164 (`+919876543210`).
- **Geo:** `{ "lat": 18.5074, "lng": 73.8077 }`.

### 1.4 Pagination (cursor)
```
GET /v1/orders?limit=20&cursor=eyJ0IjoiMjAyNi0xMS0yMFQxMDowMDowMFoiLCJpZCI6Ii4uLiJ9
```
```json
{ "data": [ ... ], "nextCursor": "eyJ0Ijoi...", "hasMore": true }
```
`limit` defaults to 20, max 50. The cursor is opaque. Offset pagination is used only in admin tables, which need page numbers (`?page=3&pageSize=50` → `{ data, total, page, pageSize }`).

### 1.5 Errors
Every non-2xx response uses this shape:
```json
{
  "error": {
    "code": "OUT_OF_STOCK",
    "message": "Only 1 unit of Front Brake Pad Set is available.",
    "details": { "productId": "1b4e…", "available": 1 },
    "requestId": "req_01JDX4…"
  }
}
```
`message` is localised and safe to show to users; `code` is stable and drives client logic.

| HTTP | code | Meaning |
|---|---|---|
| 400 | `VALIDATION_FAILED` | `details.fields: { "pincode": "must be 6 digits" }` |
| 401 | `UNAUTHENTICATED` / `TOKEN_EXPIRED` | On `TOKEN_EXPIRED` the client refreshes once, then retries |
| 403 | `FORBIDDEN` | Wrong role, not a member of that vendor, vendor not approved |
| 404 | `NOT_FOUND` | Also returned for resources the caller may not see (no existence leak) |
| 409 | `CONFLICT`, `INVALID_STATE_TRANSITION`, `IDEMPOTENCY_KEY_REUSED`, `SLOT_UNAVAILABLE`, `OUT_OF_STOCK`, `PRICE_CHANGED`, `ALREADY_REVIEWED`, `PAYOUT_IN_PROGRESS` | |
| 422 | `OTP_INVALID`, `OTP_EXPIRED`, `OTP_LOCKED`, `COD_NOT_AVAILABLE`, `OUTSIDE_DELIVERY_AREA`, `VENDOR_NOT_ACCEPTING`, `INSUFFICIENT_BALANCE`, `RETURN_WINDOW_CLOSED`, `PAYMENT_VERIFICATION_FAILED` | Business-rule failures |
| 426 | `UPGRADE_REQUIRED` | `details.storeUrl` |
| 429 | `RATE_LIMITED` | `Retry-After` header plus `details.retryAfterSeconds` |
| 5xx | `INTERNAL` | Never leaks stack traces |

### 1.6 Access levels used below
| Tag | Who |
|---|---|
| 🌐 public | no token (catalog, vendor discovery, product browsing) |
| 👤 customer | any logged-in user via the customer app |
| 🏪 vendor:`role` | member of the vendor in `X-Vendor-Id` with at least that role (`staff` < `manager` < `owner`) |
| 🛡 admin:`roles` | `users.admin_role` in the listed set (`super_admin` always allowed) |

Rate-limit defaults (Redis sliding window): authenticated 120 req/min per user, public 60 req/min per IP. Tighter limits apply to OTP and payment endpoints (see §2).

---

## 2. Auth

| Method | Path | Access | Purpose |
|---|---|---|---|
| POST | `/auth/otp/request` | 🌐 | Send OTP |
| POST | `/auth/otp/verify` | 🌐 | Verify OTP, get tokens |
| POST | `/auth/refresh` | 🌐 (refresh token) | Rotate tokens |
| POST | `/auth/logout` | 👤🏪🛡 | Revoke this session |
| POST | `/auth/logout-all` | 👤🏪🛡 | Revoke every session |

**OTP limits:** 1 request per 30 s and 5 per hour per phone; 20 per hour per IP; 5 wrong attempts lock that OTP; 3 locks in 24 h block the phone for 24 h. Codes are 6 digits, valid 5 minutes, and stored only as an HMAC.

### `POST /auth/otp/request`
```json
// request
{ "phone": "+919876543210", "purpose": "login" }
// 200
{ "otpRequestId": "5f0c…", "expiresInSeconds": 300, "resendAfterSeconds": 30 }
```
The response is identical whether or not the phone is registered (no account enumeration).

### `POST /auth/otp/verify`
```json
// request
{
  "otpRequestId": "5f0c…",
  "phone": "+919876543210",
  "code": "482913",
  "device": { "deviceId": "a1b2c3", "platform": "android", "appVersion": "1.0.0+1" }
}
// 200
{
  "accessToken": "eyJhbGciOiJFUzI1NiIs…",
  "accessTokenExpiresIn": 900,
  "refreshToken": "rt_7Hq…",            // opaque, 30 days, single use
  "isNewUser": true,
  "user": { "id": "0b6f…", "phone": "+919876543210", "fullName": null, "preferredLanguage": "en" },
  "vendorMemberships": []               // vendor app: [{ vendorId, businessName, role, status }]
}
// 422 { "error": { "code": "OTP_INVALID", "details": { "attemptsLeft": 3 } } }
```
JWT claims: `sub` (user id), `app`, `sid` (session id), `adm` (admin_role, admin app only), `iat`, `exp`. Vendor membership is **not** placed in the JWT; it is checked per request (cached in Redis for 60 s) so that removing a staff member takes effect immediately.

### `POST /auth/refresh`
```json
// request
{ "refreshToken": "rt_7Hq…" }
// 200 — same shape as verify (new pair)
```
Reusing an already-rotated refresh token revokes the whole session chain (`401 UNAUTHENTICATED`). That is the signal that the token was stolen.

---

## 3. Me: profile, devices, vehicles, addresses, notifications, wallet

| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/me` | 👤 | Profile + counts (cart items, unread notifications) |
| PATCH | `/me` | 👤 | `fullName`, `email`, `preferredLanguage`, `avatarPublicId` |
| DELETE | `/me` | 👤 | Body `{ otpRequestId, code }` (purpose `delete_account`). Blocked with `409` if there are open orders, bookings or disputes. Anonymises PII and sets `deleted_at` |
| POST | `/me/devices` | 👤🏪 | `{ fcmToken, platform, locale }`. Upsert |
| DELETE | `/me/devices/{fcmToken}` | 👤🏪 | On logout |
| GET | `/me/vehicles` | 👤 | |
| POST | `/me/vehicles` | 👤 | |
| PATCH | `/me/vehicles/{id}` | 👤 | |
| DELETE | `/me/vehicles/{id}` | 👤 | Soft delete |
| GET | `/me/vehicles/{id}/history` | 👤 | Completed bookings + parts orders for this car |
| GET / POST / PATCH / DELETE | `/me/addresses[/{id}]` | 👤 | |
| GET | `/me/notifications?app=customer` | 👤🏪 | Cursor paginated |
| POST | `/me/notifications/read` | 👤🏪 | `{ ids: [..] }` or `{ all: true }` |
| GET | `/me/wallet` | 👤 | `{ balancePaise, expiringSoon: [{ amountPaise, expiresAt }] }` |
| GET | `/me/wallet/transactions` | 👤 | Cursor paginated |
| GET | `/me/favorites/vendors` | 👤 | |
| PUT / DELETE | `/me/favorites/vendors/{vendorId}` | 👤 | |

### `POST /me/vehicles`
```json
// request
{
  "makeId": 1, "modelId": 1, "variantId": 3,
  "manufactureYear": 2021, "fuelType": "petrol", "transmission": "manual",
  "registrationNumber": "MH 12 AB 1234",       // server normalises → "MH12AB1234"
  "nickname": "Daily Swift", "odometerKm": 42000, "isDefault": true
}
// 201
{
  "id": "7d1e…", "make": { "id": 1, "name": "Maruti Suzuki" }, "model": { "id": 1, "name": "Swift", "bodyType": "hatchback" },
  "variant": { "id": 3, "name": "LXi/VXi/ZXi 1.2 Z-Series" },
  "manufactureYear": 2021, "fuelType": "petrol", "transmission": "manual",
  "registrationNumber": "MH12AB1234", "nickname": "Daily Swift", "odometerKm": 42000, "isDefault": true
}
```

### `POST /me/addresses`
```json
{
  "label": "home", "contactName": "Rahul Patil", "contactPhone": "+919876543210",
  "line1": "Flat 302, Sai Residency", "line2": "Karve Nagar", "landmark": "Near Kamins Hospital",
  "city": "Pune", "state": "Maharashtra", "pincode": "411052",
  "location": { "lat": 18.4893, "lng": 73.8203 }, "isDefault": true
}
```

---

## 4. Catalog (reference data, offline-cached)

| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/catalog/bootstrap` | 🌐 | Everything the app caches at launch, in one ETag'd response (~40 KB gzipped) |
| GET | `/catalog/categories?domain=parts` | 🌐 | With subcategories |
| GET | `/catalog/brands` | 🌐 | |
| GET | `/catalog/makes` | 🌐 | |
| GET | `/catalog/makes/{makeId}/models` | 🌐 | |
| GET | `/catalog/models/{modelId}/variants` | 🌐 | |

### `GET /catalog/bootstrap`
```json
// 200  ETag: "cat-2026-11-25T10:00:00Z"
{
  "version": "2026-11-25T10:00:00Z",
  "categories": [
    { "id": 2, "domain": "parts", "slug": "brakes", "name": "Brakes", "iconUrl": "…",
      "subcategories": [ { "id": 5, "slug": "brake-pads", "name": "Brake Pads" } ] }
  ],
  "brands": [ { "id": 5, "name": "Bosch", "isVehicleOem": false } ],
  "makes": [ { "id": 1, "name": "Maruti Suzuki", "logoUrl": "…",
               "models": [ { "id": 1, "name": "Swift", "bodyType": "hatchback" } ] } ],
  "config": {
    "minAppVersion": { "android": "1.0.0", "ios": "1.0.0" },
    "codMaxPaise": 500000, "supportPhone": "+9120…", "cities": ["Pune"]
  }
}
```
`name` is resolved from `Accept-Language`. Admin endpoints return the full `nameI18n` object instead.

---

## 5. Spare parts: browse and search (customer)

| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/products` | 🌐 (👤 adds personal fit info) | Search + filter |
| GET | `/products/{id}` | 🌐 | Detail |
| GET | `/products/{id}/reviews` | 🌐 | Cursor paginated |
| GET | `/products/suggest?q=brak` | 🌐 | Type-ahead: product names, part numbers, subcategories (max 8) |

### `GET /products`
| Param | Type | Example | Notes |
|---|---|---|---|
| `q` | string | `brake pad` | Full text over name / part number / SKU, with trigram fallback for typos |
| `vehicleId` | uuid | | Only parts that fit this car (plus universal-fit parts) |
| `makeId`, `modelId`, `year` | int | | Same, for guests without a saved vehicle |
| `subcategoryId` | int | `5` | |
| `brandId` | int[] | `5,13` | |
| `partType` | enum[] | `oem,oes` | |
| `condition` | enum | `new` | |
| `minPricePaise`, `maxPricePaise` | int | | |
| `inStock` | bool | `true` | default `true` |
| `lat`, `lng`, `radiusKm` | | | Limit to vendors that deliver here (default: saved address) |
| `sort` | enum | `relevance \| price_asc \| price_desc \| rating \| nearest \| newest` | |
| `cursor`, `limit` | | | |

```json
// 200
{
  "data": [
    {
      "id": "1b4e…",
      "name": "Front Brake Pad Set",
      "brand": { "id": 5, "name": "Bosch" },
      "partNumber": "55810M68K00",
      "partType": "oes",
      "condition": "new",
      "mrpPaise": 180000,
      "pricePaise": 149900,
      "discountPercent": 16,
      "thumbnailUrl": "https://res.cloudinary.com/autohub/image/upload/f_auto,q_auto,w_320/p/1b4e/0.jpg",
      "rating": { "avg": 4.3, "count": 57 },
      "inStock": true,
      "fit": "fits",                       // fits | universal | unknown | does_not_fit (only when a vehicle is known)
      "vendor": { "id": "b1…", "businessName": "Shree Auto Parts", "distanceKm": 3.2, "rating": 4.5 },
      "deliveryEta": "today"               // today | tomorrow | 2-3_days
    }
  ],
  "facets": {
    "brands": [ { "id": 5, "name": "Bosch", "count": 12 } ],
    "partType": { "oem": 3, "oes": 12, "aftermarket": 20 },
    "priceRangePaise": { "min": 49900, "max": 450000 }
  },
  "nextCursor": "…", "hasMore": true
}
```
**Offline:** the app stores each result page in its SQLite response cache, keyed by the normalised query plus the ETag. Opening a cached search offline shows it immediately with an "offline, prices may have changed" banner. Prices and stock are always re-checked at `POST /checkout/quote`.

### `GET /products/{id}`
```json
{
  "id": "1b4e…", "sku": "BP-SW-01", "name": "Front Brake Pad Set", "description": "Ceramic, low dust…",
  "brand": { "id": 5, "name": "Bosch" }, "partNumber": "55810M68K00", "partType": "oes", "condition": "new",
  "subcategory": { "id": 5, "name": "Brake Pads", "categoryId": 2 },
  "mrpPaise": 180000, "pricePaise": 149900, "gstRateBps": 1800, "hsnCode": "87083000",
  "stock": { "inStock": true, "lowStock": false, "maxPerOrder": 10 },
  "warrantyMonths": 6, "returnWindowDays": 7,
  "images": [ { "url": "…/w_800/…", "thumbUrl": "…/w_320/…" } ],
  "fitments": [ { "make": "Maruti Suzuki", "model": "Swift", "variant": null, "fuelType": null, "yearFrom": 2018, "yearTo": null } ],
  "isUniversalFit": false,
  "fitForVehicle": { "vehicleId": "7d1e…", "fit": "fits" },
  "rating": { "avg": 4.3, "count": 57, "distribution": { "5": 30, "4": 15, "3": 7, "2": 3, "1": 2 } },
  "vendor": { "id": "b1…", "businessName": "Shree Auto Parts", "rating": 4.5, "distanceKm": 3.2,
              "codEnabled": true, "phone": "+919800000002" },
  "otherSellers": [ { "productId": "9c…", "vendorName": "Om Motors", "pricePaise": 154900, "distanceKm": 5.1 } ]
}
```
`otherSellers` lists products with the same `partNumber` + brand from other vendors, so customers can compare prices.

---

## 6. Vendor discovery: service centres, decorators, parts shops

| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/vendors/nearby` | 🌐 | Map + list |
| GET | `/vendors/{id}` | 🌐 | Shop profile (accepts id or slug) |
| GET | `/vendors/{id}/services?domain=service&vehicleId=` | 🌐 | Prices filtered to the vehicle's fuel and body type |
| GET | `/vendors/{id}/products` | 🌐 | Same filters as `/products` |
| GET | `/vendors/{id}/reviews` | 🌐 | |
| GET | `/vendors/{id}/slots?date=2026-12-01&serviceIds=..` | 🌐 | Free slots |
| GET | `/services/search?q=&subcategoryId=&lat=&lng=` | 🌐 | "AC gas refill near me" across vendors, sorted by price/distance/rating |

### `GET /vendors/nearby`
Params: `lat`, `lng` (required), `radiusKm` (default 10, max 50), `domain` (`parts|service|decor`), `subcategoryId`, `minRating`, `openNow`, `doorstep`, `sort` (`distance|rating|price`), `bbox` (`minLng,minLat,maxLng,maxLat`, used instead of radius when the map is panned), `cursor`, `limit`.
```json
{
  "data": [
    {
      "id": "b1…", "slug": "shree-auto", "businessName": "Shree Auto Parts & Service",
      "domains": ["parts", "service"], "logoUrl": "…", "coverUrl": "…",
      "location": { "lat": 18.5074, "lng": 73.8077 }, "distanceKm": 7.4,
      "address": "Paud Road, Kothrud, Pune 411038",
      "rating": { "avg": 4.0, "count": 2 }, "isOpenNow": true, "closesAt": "20:00",
      "offersDoorstep": false,
      "highlight": { "serviceName": "AC Gas Refill", "fromPricePaise": 149900 }   // when subcategoryId given
    }
  ],
  "nextCursor": null, "hasMore": false
}
```

### `GET /vendors/{id}/slots?date=2026-12-01`
```json
{
  "date": "2026-12-01", "timezone": "Asia/Kolkata",
  "slots": [
    { "id": "f1…", "startsAt": "2026-12-01T04:30:00Z", "localTime": "10:00", "available": 1 },
    { "id": "f2…", "startsAt": "2026-12-01T05:30:00Z", "localTime": "11:00", "available": 0 }
  ],
  "nextAvailableDate": "2026-12-01"
}
```

---

## 7. Cart, checkout and orders (customer)

| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/cart` | 👤 | Grouped by vendor, with live price/stock/fit checks |
| PUT | `/cart/items/{productId}` | 👤 | `{ quantity }` (0 removes) |
| DELETE | `/cart/items/{productId}` | 👤 | |
| PATCH | `/cart` | 👤 | `{ vehicleId }` |
| DELETE | `/cart` | 👤 | Clear |
| POST | `/checkout/quote` | 👤 | Price preview: delivery, wallet, COD eligibility, warnings |
| POST | `/checkout` | 👤 · **Idempotency-Key** | Creates order group + orders + Razorpay order |
| GET | `/orders` | 👤 | `?status=active\|past` |
| GET | `/orders/{id}` | 👤 | Detail + timeline |
| POST | `/orders/{id}/cancel` | 👤 | Allowed before `dispatched` |
| GET | `/orders/{id}/invoice` | 👤 | `{ url, expiresAt }`: 10-minute signed URL to the GST invoice PDF |
| POST | `/orders/{id}/items/{itemId}/returns` | 👤 | Return request |
| GET | `/returns/{id}` | 👤 | |
| POST | `/returns/{id}/cancel` | 👤 | |

### `GET /cart`
```json
{
  "vehicle": { "id": "7d1e…", "label": "Swift 2021 · MH12AB1234" },
  "groups": [
    {
      "vendor": { "id": "b1…", "businessName": "Shree Auto Parts", "codEnabled": true, "deliversToDefaultAddress": true },
      "items": [
        { "productId": "1b4e…", "name": "Front Brake Pad Set", "thumbnailUrl": "…", "quantity": 2,
          "unitPricePaise": 149900, "mrpPaise": 180000, "lineTotalPaise": 299800,
          "fit": "fits", "issues": [] }
      ],
      "itemsTotalPaise": 299800
    }
  ],
  "itemsTotalPaise": 299800, "savingsPaise": 60200, "itemCount": 2,
  "issues": []        // e.g. { "code": "PRICE_CHANGED", "productId": "…", "oldPaise": 139900, "newPaise": 149900 }
}
```

### `POST /checkout/quote`
```json
// request
{ "addressId": "a9…", "paymentMode": "prepaid", "useWallet": true }
// 200
{
  "orders": [
    { "vendorId": "b1…", "itemsTotalPaise": 299800, "deliveryFeePaise": 0, "taxPaise": 45732, "totalPaise": 299800,
      "expectedDeliveryAt": "2026-11-26T12:30:00Z" }
  ],
  "itemsTotalPaise": 299800, "deliveryFeePaise": 0, "discountPaise": 0,
  "walletAvailablePaise": 15000, "walletAppliedPaise": 15000,
  "payablePaise": 284800,
  "cod": { "available": true, "reason": null },
  "issues": []
}
```

### `POST /checkout`
```
Idempotency-Key: 3a6f1b7e-…
```
```json
// request
{ "addressId": "a9…", "paymentMode": "prepaid", "useWallet": true, "customerNote": "Call before delivery",
  "expectedPayablePaise": 284800 }
```
`expectedPayablePaise` guards against silent price changes. If the server's total differs, it returns `409 PRICE_CHANGED` with the new quote.
```json
// 201 — prepaid
{
  "orderGroupId": "d1…",
  "orders": [ { "id": "e1…", "orderNumber": "ORD-261125-000001", "vendorId": "b1…", "totalPaise": 299800, "status": "pending_payment" } ],
  "payment": {
    "paymentId": "p1…",
    "razorpay": {
      "keyId": "rzp_live_xxxxx",
      "orderId": "order_PqR8…",
      "amountPaise": 284800,
      "currency": "INR",
      "name": "AutoHub",
      "description": "Order ORD-261125-000001",
      "prefill": { "contact": "+919876543210", "name": "Rahul Patil" }
    },
    "expiresAt": "2026-11-25T11:00:00Z"
  }
}
// 201 — COD: "payment": null, orders already "placed"
```
Stock is reserved for 30 minutes. If payment isn't captured by then, the orders become `payment_failed` and the stock is released.

### `GET /orders/{id}`
```json
{
  "id": "e1…", "orderNumber": "ORD-261125-000001", "status": "dispatched", "paymentMode": "prepaid", "paymentState": "paid",
  "vendor": { "id": "b1…", "businessName": "Shree Auto Parts", "phone": "+919800000002" },
  "items": [ { "id": "i1…", "productId": "1b4e…", "name": "Front Brake Pad Set", "quantity": 2, "unitPricePaise": 149900,
               "lineTotalPaise": 299800, "returnable": false, "returnWindowEndsAt": null, "review": null } ],
  "shippingAddress": { "contactName": "Rahul Patil", "line1": "Flat 302…", "city": "Pune", "pincode": "411052" },
  "totals": { "itemsTotalPaise": 299800, "discountPaise": 0, "deliveryFeePaise": 0, "taxPaise": 45732, "totalPaise": 299800 },
  "tracking": { "courierName": "Shop delivery", "trackingNumber": null, "trackingUrl": null, "expectedDeliveryAt": "2026-11-26T12:30:00Z" },
  "timeline": [
    { "status": "placed",     "at": "2026-11-25T10:31:00Z" },
    { "status": "accepted",   "at": "2026-11-25T10:40:00Z" },
    { "status": "packed",     "at": "2026-11-25T11:15:00Z" },
    { "status": "dispatched", "at": "2026-11-25T12:02:00Z", "note": "Rider: Sunil" }
  ],
  "actions": { "canCancel": false, "canReturn": false, "canReview": false, "canRaiseDispute": true, "canChat": true }
}
```
`actions` is computed by the server, so both apps stay consistent with the state machine (§12).

### `POST /orders/{orderId}/items/{itemId}/returns`
```json
{ "quantity": 1, "reason": "does_not_fit", "description": "Pads are for the 2017 model", "photoPublicIds": ["ret/…/1"] }
// 201 { "id": "r1…", "status": "requested", ... }
// 422 RETURN_WINDOW_CLOSED
```

---

## 8. Payments

| Method | Path | Access | Notes |
|---|---|---|---|
| POST | `/payments/verify` | 👤 | Called by the app after Razorpay success |
| GET | `/payments/{id}` | 👤 | Status polling fallback (app killed, UPI pending) |
| POST | `/bookings/{id}/payments` | 👤 | Create a Razorpay order for a booking advance or balance |
| POST | `/webhooks/razorpay` | Razorpay only | HMAC `X-Razorpay-Signature`, deduped on `X-Razorpay-Event-Id` |

### `POST /payments/verify`
Limit: 10/min per user.
```json
// request (straight from the Razorpay SDK success callback)
{ "razorpayOrderId": "order_PqR8…", "razorpayPaymentId": "pay_Ps2a…", "razorpaySignature": "9e1f…" }
// 200
{ "paymentId": "p1…", "status": "captured", "orderGroupId": "d1…", "orders": [ { "id": "e1…", "status": "placed" } ] }
// 422 PAYMENT_VERIFICATION_FAILED   (bad signature, amount mismatch, or order not owned by caller)
// 202 { "status": "authorized" }    (UPI still pending; app polls GET /payments/{id} or waits for push)
```
Server steps:
1. `HMAC_SHA256(orderId|paymentId, key_secret)` must equal the signature (constant-time compare).
2. Fetch the payment from the Razorpay API, and check `order_id`, `amount`, `currency=INR` and `status` against our `payments` row.
3. In one transaction, mark it captured and move the orders to `placed`, idempotently.

The webhook does the same on its own, so whichever arrives first wins. The client's word is never trusted.

### `POST /bookings/{id}/payments`
```json
// request
{ "purpose": "booking_balance", "useWallet": false }
// 201 — same "payment" object as checkout
```

### `POST /webhooks/razorpay`
Handled events: `payment.authorized`, `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`, `refund.failed`, `transfer.processed`, `payout.processed`, `payout.reversed`.
The endpoint verifies the signature over the **raw body**, inserts into `payment_webhook_events` (a unique event id makes retries no-ops), returns `200` within 100 ms, and processes the event in the worker.

---

## 9. Bookings: services and decor (customer)

| Method | Path | Access | Notes |
|---|---|---|---|
| POST | `/media/upload-signature` | 👤🏪 | Direct-to-Cloudinary/S3 upload params (see §11) |
| POST | `/bookings/quote` | 👤 | Price preview for the selected services + vehicle |
| POST | `/bookings` | 👤 · **Idempotency-Key** | Create |
| GET | `/bookings` | 👤 | `?status=active\|past` |
| GET | `/bookings/{id}` | 👤 | Detail, estimates, timeline, attachments |
| POST | `/bookings/{id}/cancel` | 👤 | Free until 2 h before the slot; advance refunded to source |
| POST | `/bookings/{id}/reschedule` | 👤 | `{ slotId }`; before `vehicle_received` |
| POST | `/bookings/{id}/attachments` | 👤 | `{ kind: "issue_photo", publicId, caption }` |
| POST | `/bookings/{id}/estimates/{estimateId}/approve` | 👤 | `{ declinedItemIds: [] }` (optional items only) |
| POST | `/bookings/{id}/estimates/{estimateId}/reject` | 👤 | `{ reason }` → vendor can revise or close |

### `POST /bookings`
```
Idempotency-Key: 9b2c…
```
```json
// request
{
  "vendorId": "b1…",
  "vehicleId": "7d1e…",
  "serviceIds": ["s1…", "s2…"],
  "slotId": "f1…",
  "locationType": "at_shop",                 // at_shop | doorstep | pickup_drop
  "addressId": null,                          // required unless at_shop
  "customerNotes": "AC not cooling, noise from front left wheel",
  "attachments": [ { "kind": "issue_photo", "publicId": "bk/tmp/u_0b6f/abc" } ],
  "odometerKm": 42150,
  "payAdvance": true
}
// 201
{
  "id": "a9…", "bookingNumber": "BKG-261125-000001", "status": "requested",
  "scheduledStart": "2026-12-01T04:30:00Z",
  "vendor": { "id": "b1…", "businessName": "Shree Auto Parts & Service", "phone": "+919800000002",
              "location": { "lat": 18.5074, "lng": 73.8077 } },
  "services": [
    { "serviceId": "s1…", "name": "AC Gas Refill (R134a)", "priceType": "fixed", "pricePaise": 149900 },
    { "serviceId": "s2…", "name": "Suspension inspection", "priceType": "on_inspection", "pricePaise": null }
  ],
  "quotedTotalPaise": 149900,
  "advancePaise": 20000,
  "payment": { "paymentId": "p2…", "razorpay": { "orderId": "order_Q1…", "amountPaise": 20000, "keyId": "…", "currency": "INR" } }
}
// 409 SLOT_UNAVAILABLE   { "details": { "nextSlots": [ … ] } }
```
The slot is held at creation. If the advance isn't paid within 15 minutes, the booking is cancelled (`cancelled_by: system`) and the slot released.

### `GET /bookings/{id}`
```json
{
  "id": "a9…", "bookingNumber": "BKG-261125-000001", "status": "estimate_shared",
  "vehicle": { "id": "7d1e…", "label": "Swift 2021 · MH12AB1234" },
  "scheduledStart": "2026-12-01T04:30:00Z", "locationType": "at_shop",
  "services": [ … ],
  "estimate": {
    "id": "es1…", "version": 2, "status": "pending", "validUntil": "2026-12-01T12:00:00Z",
    "items": [
      { "id": "ei1…", "kind": "service", "description": "AC Gas Refill (R134a)", "quantity": 1, "unitPricePaise": 149900, "gstRateBps": 1800, "isOptional": false },
      { "id": "ei2…", "kind": "part",    "description": "Front-left stabiliser link", "quantity": 1, "unitPricePaise": 95000, "gstRateBps": 1800, "isOptional": false },
      { "id": "ei3…", "kind": "labour",  "description": "Link replacement labour", "quantity": 1, "unitPricePaise": 55100, "gstRateBps": 1800, "isOptional": false },
      { "id": "ei4…", "kind": "service", "description": "Wheel alignment (recommended)", "quantity": 1, "unitPricePaise": 59100, "gstRateBps": 1800, "isOptional": true }
    ],
    "subtotalPaise": 359100, "taxPaise": 64638, "totalPaise": 423738,
    "ifOptionalDeclined": { "subtotalPaise": 300000, "taxPaise": 54000, "totalPaise": 354000 },
    "vendorNote": "Stabiliser link worn out — photos attached"
  },
  "payments": { "amountPaidPaise": 20000, "balanceDuePaise": null, "paymentState": "partially_paid" },   // known once the estimate is approved,
  "attachments": [ { "kind": "inspection_photo", "url": "…", "uploadedBy": "vendor" } ],
  "timeline": [ { "status": "requested", "at": "…" }, { "status": "confirmed", "at": "…" },
                { "status": "vehicle_received", "at": "…" }, { "status": "estimate_shared", "at": "…" } ],
  "actions": { "canCancel": false, "canReschedule": false, "canApproveEstimate": true, "canPay": false, "canReview": false, "canChat": true }
}
```
> Estimate prices are **tax-exclusive** (`subtotal + tax = total`), matching how Indian workshops write job cards. Parts listings are tax-inclusive (MRP). The API labels which is which with `subtotalPaise`/`taxPaise`.

---

## 10. Reviews, chat, disputes (customer side)

| Method | Path | Access | Notes |
|---|---|---|---|
| POST | `/reviews` | 👤 | Only after `delivered` / `completed` |
| PATCH | `/reviews/{id}` | 👤 (author) | Within 30 days |
| DELETE | `/reviews/{id}` | 👤 (author) | |
| POST | `/reviews/{id}/report` | 👤🏪 | `{ reason, note }`; one per user |
| GET | `/chat/conversations` | 👤🏪 | Customer: mine. Vendor (with `X-Vendor-Id`): the shop's |
| POST | `/chat/conversations` | 👤 | `{ vendorId }`, get-or-create |
| GET | `/chat/conversations/{id}/messages?beforeId=&limit=30` | 👤🏪 | Newest first |
| POST | `/chat/conversations/{id}/messages` | 👤🏪 | REST fallback when the socket is down |
| POST | `/chat/conversations/{id}/read` | 👤🏪 | `{ lastReadId }` |
| POST | `/vendors/{id}/call-click` | 👤 | Analytics counter; the app then opens the dialer |
| POST | `/disputes` | 👤🏪 | |
| GET | `/disputes` | 👤🏪 | |
| GET | `/disputes/{id}` | 👤🏪 | Internal admin notes excluded |
| POST | `/disputes/{id}/messages` | 👤🏪 | `{ body, attachmentPublicIds }` |

### `POST /reviews`
```json
{ "orderId": "e1…", "productId": "1b4e…", "rating": 4, "title": "Good fit", "body": "Exact fit for my 2021 Swift.",
  "mediaPublicIds": ["rv/tmp/u_0b6f/x1"] }
// or { "bookingId": "a9…", "rating": 5, "body": "Explained everything with photos." }
// 409 ALREADY_REVIEWED
```
Reviews with photos or flagged words start as `pending`; others publish immediately.

### `POST /disputes`
```json
{ "orderId": "e1…", "reason": "wrong_or_damaged_part", "description": "Received pads for a different model",
  "claimedAmountPaise": 149900, "attachmentPublicIds": ["dp/tmp/…"] }
// 201 { "id": "…", "disputeNumber": "DSP-261125-000001", "status": "open", "slaDueAt": "2026-11-28T10:00:00Z" }
```

### Socket.IO: `wss://api.autohub.in/ws`
Connect with `auth: { token: <accessToken>, app: "customer" | "vendor", vendorId? }`. The server joins the socket to rooms `user:<id>`, `vendor:<id>` and `conv:<id>` (each checked against membership).

| Direction | Event | Payload |
|---|---|---|
| client → server | `chat:send` (with ack) | `{ conversationId, clientMsgId, type, body?, attachmentPublicId?, orderId?, bookingId? }` → ack `{ id, createdAt }` |
| server → client | `chat:message` | full message object |
| client → server | `chat:typing` | `{ conversationId }` (throttled to 1 per 3 s) |
| client → server | `chat:read` | `{ conversationId, lastReadId }` |
| server → client | `order:updated` | `{ orderId, status, at }` |
| server → client | `booking:updated` | `{ bookingId, status, at }` |
| server → client | `notification` | in-app banner payload |

`clientMsgId` makes resends after a dropped connection safe (unique index in the DB). When the app is backgrounded, the same events arrive as FCM pushes.

---

## 11. Media uploads

Files go **directly** from the phone to Cloudinary or S3. The API only signs the upload, so large photos never pass through the API servers.

### `POST /media/upload-signature`
```json
// request
{ "purpose": "booking_issue", "contentType": "image/jpeg", "sizeBytes": 412300 }
// 200 — Cloudinary (public images)
{
  "provider": "cloudinary",
  "uploadUrl": "https://api.cloudinary.com/v1_1/autohub/image/upload",
  "fields": { "api_key": "…", "timestamp": 1764067200, "signature": "…", "folder": "bk/tmp/u_0b6f",
              "allowed_formats": "jpg,png,webp,heic", "max_file_size": 8000000 },
  "publicIdPrefix": "bk/tmp/u_0b6f/"
}
// 200 — S3 (vendor KYC documents, private)
{ "provider": "s3", "uploadUrl": "https://autohub-kyc.s3.ap-south-1.amazonaws.com/…?X-Amz-Signature=…",
  "method": "PUT", "headers": { "Content-Type": "application/pdf" }, "storageKey": "kyc/b1…/2f…", "expiresInSeconds": 300 }
```
| `purpose` | Store | Max | Who |
|---|---|---|---|
| `avatar`, `review_photo`, `booking_issue`, `chat_image`, `return_photo`, `dispute_evidence` | Cloudinary | 8 MB | 👤 |
| `product_image`, `service_image`, `vendor_logo`, `vendor_cover`, `inspection_photo` | Cloudinary | 8 MB | 🏪 |
| `vendor_document` | S3 private | 10 MB | 🏪 owner |

When a `publicId`/`storageKey` comes back in a later request, the server checks that it starts with the caller's own prefix, so nobody can attach someone else's upload. The app compresses images to ≤ 1600 px / JPEG q80 before uploading, which matters on 3G.

---

## 12. State machines (enforced server-side)

### Orders
| From → To | Who | Endpoint |
|---|---|---|
| `pending_payment` → `placed` | system (payment captured) | verify / webhook |
| `pending_payment` → `payment_failed` | system (30 min) | sweeper |
| `placed` → `accepted` / `rejected` | vendor | `/vendor/orders/{id}/accept`, `/reject` |
| `placed` → `rejected` | system (vendor silent 4 h) | sweeper |
| `accepted` → `packed` → `dispatched` → `out_for_delivery` → `delivered` | vendor | `/pack`, `/dispatch`, `/out-for-delivery`, `/deliver` |
| `placed`, `accepted`, `packed` → `cancelled` | customer, vendor, admin | `/cancel` |
| any non-final → `cancelled` | admin | `/admin/orders/{id}/cancel` |

`rejected` and `cancelled` on a prepaid order trigger an automatic full refund to source. `delivered` sets `return_window_ends_at` on each item and creates an `order_earning` ledger entry that becomes available after the window closes.

### Bookings
| From → To | Who |
|---|---|
| `requested` → `confirmed` / `rejected` | vendor (auto-reject after 2 h, or 1 h before the slot) |
| `confirmed` → `vehicle_received` | vendor (`/check-in`) |
| `confirmed` → `no_show` | vendor, 30 min after slot start |
| `vehicle_received` / `in_progress` → `estimate_shared` | vendor (new estimate version; previous one `superseded`) |
| `estimate_shared` → `in_progress` | customer approves |
| `vehicle_received` → `in_progress` | vendor, only if every booked service is `fixed` price (no estimate needed) |
| `in_progress` → `ready` | vendor |
| `ready` → `completed` | system when fully paid, or vendor records an offline cash payment |
| `requested`, `confirmed` → `cancelled` | customer, vendor, admin |

Each transition writes a `*_status_history` row, emits a socket event and a push, and is audited when an admin does it. An invalid move returns `409 INVALID_STATE_TRANSITION` with `details.allowed`.

---

## 13. Vendor API (`/vendor/*`, header `X-Vendor-Id`)

### 13.1 Onboarding
| Method | Path | Access | Notes |
|---|---|---|---|
| POST | `/vendor-registrations` | 👤 (vendor app, no `X-Vendor-Id`) | Creates a `draft` vendor; caller becomes `owner` |
| GET | `/me/vendors` | 👤 | My memberships |
| GET | `/vendor/onboarding` | 🏪 owner | Checklist + status + rejection reason |
| GET / PATCH | `/vendor/profile` | 🏪 manager | Name, description, hours, logo, delivery radius, COD, doorstep |
| POST | `/vendor/profile/submit` | 🏪 owner | `draft`/`rejected` → `pending_review`; checks required documents |
| PATCH | `/vendor/profile/accepting-orders` | 🏪 manager | `{ isAcceptingOrders }`, the "shop closed" toggle |
| GET / POST / DELETE | `/vendor/documents[/{id}]` | 🏪 owner | Delete only while `pending` |
| GET / POST | `/vendor/bank-accounts` | 🏪 owner | Triggers penny-drop verification |
| PATCH | `/vendor/bank-accounts/{id}/primary` | 🏪 owner | |
| GET / POST / DELETE | `/vendor/members[/{userId}]` | 🏪 owner | Invite by phone; role `manager`/`staff` |

Required documents: everyone needs `pan_card`, `owner_id_proof`, `shop_photo` and `cancelled_cheque`. Parts sellers also need `gst_certificate`. Service centres and decorators need `gst_certificate` **or** `udyam_certificate` + `shop_establishment_license`.

```json
// POST /vendor-registrations
{
  "businessName": "Shree Auto Parts & Service", "businessDomains": ["parts", "service"],
  "legalName": "Shree Auto Parts", "gstin": "27AAPFU0939F1ZV", "pan": "AAPFU0939F",
  "phone": "+919800000002", "email": "shree@example.com",
  "address": { "line1": "Paud Road", "city": "Pune", "state": "Maharashtra", "pincode": "411038" },
  "location": { "lat": 18.5074, "lng": 73.8077 }
}
// 201 { "id": "b1…", "status": "draft", "slug": "shree-auto-parts-service" }

// POST /vendor/documents  (after uploading to S3 with a vendor_document signature)
{ "docType": "gst_certificate", "docNumber": "27AAPFU0939F1ZV", "storageKey": "kyc/b1…/2f…",
  "mimeType": "application/pdf", "sizeBytes": 223001 }

// GET /vendor/onboarding
{
  "status": "rejected", "statusReason": "GST certificate is not legible — please re-upload.",
  "checklist": [
    { "item": "profile",           "done": true },
    { "item": "gst_certificate",   "done": false, "documentStatus": "rejected", "note": "Not legible" },
    { "item": "pan_card",          "done": true,  "documentStatus": "verified" },
    { "item": "bank_account",      "done": true },
    { "item": "working_hours",     "done": true },
    { "item": "first_listing",     "done": false }
  ],
  "canSubmit": false
}
```

### 13.2 Inventory (spare parts)
| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/vendor/products` | 🏪 staff | `?q=&status=&lowStock=true&subcategoryId=` |
| POST | `/vendor/products` | 🏪 manager | |
| GET / PATCH / DELETE | `/vendor/products/{id}` | 🏪 manager | DELETE = soft delete |
| POST | `/vendor/products/{id}/images` | 🏪 manager | `{ publicId, sortOrder }` (max 8) |
| DELETE | `/vendor/products/{id}/images/{imageId}` | 🏪 manager | |
| PUT | `/vendor/products/{id}/fitments` | 🏪 manager | Replaces the full fitment list |
| POST | `/vendor/products/{id}/stock` | 🏪 staff | `{ delta, reason: "restock"\|"adjustment", note }` |
| GET | `/vendor/products/{id}/stock-movements` | 🏪 manager | Audit trail |

```json
// POST /vendor/products
{
  "subcategoryId": 5, "brandId": 5, "sku": "BP-SW-01", "name": "Front Brake Pad Set",
  "description": "Ceramic, low dust", "partNumber": "55810M68K00", "partType": "oes", "condition": "new",
  "mrpPaise": 180000, "pricePaise": 149900, "gstRateBps": 1800, "hsnCode": "87083000",
  "stockQty": 10, "lowStockThreshold": 3, "maxPerOrder": 4, "weightGrams": 1200,
  "warrantyMonths": 6, "returnWindowDays": 7, "isUniversalFit": false, "status": "active",
  "fitments": [ { "makeId": 1, "modelId": 1, "yearFrom": 2018, "yearTo": null } ]
}
```
Validation: `pricePaise ≤ mrpPaise`; HSN 4–8 digits; SKU unique per shop; `status: active` requires at least one image and (`isUniversalFit` or one fitment).

### 13.3 Service & decor catalog
| Method | Path | Access |
|---|---|---|
| GET / POST | `/vendor/services` | 🏪 staff / manager |
| GET / PATCH / DELETE | `/vendor/services/{id}` | 🏪 manager |
| POST / DELETE | `/vendor/services/{id}/images[/{imageId}]` | 🏪 manager |

```json
// POST /vendor/services
{
  "subcategoryId": 28, "name": "AC Gas Refill (R134a)", "description": "Leak test + refill up to 600 g",
  "inclusions": ["Leak test", "Gas up to 600 g", "Cooling check"],
  "priceType": "fixed", "pricePaise": 149900, "gstRateBps": 1800, "sacCode": "998714",
  "durationMinutes": 90, "applicableFuelTypes": null, "applicableBodyTypes": ["hatchback", "sedan"],
  "warrantyDays": 30, "advancePaise": 20000, "doorstepAvailable": false, "status": "active"
}
```
SUV pricing: create a second service with `applicableBodyTypes: ["suv","muv"]`. Customers only see the variant that matches their vehicle.

### 13.4 Schedule
| Method | Path | Access | Notes |
|---|---|---|---|
| GET / PUT | `/vendor/working-hours` | 🏪 manager | Replaces the weekly template; future empty slots are regenerated |
| GET / POST / DELETE | `/vendor/holidays[/{date}]` | 🏪 manager | Blocks the day's slots; `409` if bookings exist unless `?force=true` (customers notified, advances refunded) |
| GET | `/vendor/slots?from=2026-12-01&to=2026-12-07` | 🏪 staff | Calendar with bookings |
| PATCH | `/vendor/slots/{id}` | 🏪 manager | `{ isBlocked?, capacity? }` (capacity ≥ booked) |

```json
// PUT /vendor/working-hours
{ "days": [
  { "weekday": 1, "opensAt": "09:30", "closesAt": "13:30", "slotMinutes": 60, "capacityPerSlot": 3 },
  { "weekday": 1, "opensAt": "14:30", "closesAt": "19:30", "slotMinutes": 60, "capacityPerSlot": 3 }
] }
```

### 13.5 Orders & returns
| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/vendor/orders` | 🏪 staff | `?status=new\|active\|completed\|cancelled&cursor=` |
| GET | `/vendor/orders/{id}` | 🏪 staff | Customer phone masked until `accepted` |
| POST | `/vendor/orders/{id}/accept` | 🏪 staff | `{ expectedDeliveryAt? }` |
| POST | `/vendor/orders/{id}/reject` | 🏪 staff | `{ reason: "out_of_stock"\|"cannot_deliver"\|"other", note }` → auto-refund |
| POST | `/vendor/orders/{id}/pack` | 🏪 staff | |
| POST | `/vendor/orders/{id}/dispatch` | 🏪 staff | `{ courierName, trackingNumber?, trackingUrl?, expectedDeliveryAt? }` |
| POST | `/vendor/orders/{id}/out-for-delivery` | 🏪 staff | |
| POST | `/vendor/orders/{id}/deliver` | 🏪 staff | COD: `{ cashCollectedPaise }` must equal total |
| GET | `/vendor/returns` | 🏪 staff | |
| POST | `/vendor/returns/{id}/approve` | 🏪 manager | `{ refundAmountPaise? }` (defaults to the item price × qty) |
| POST | `/vendor/returns/{id}/reject` | 🏪 manager | `{ note }`; customer can escalate to a dispute |
| POST | `/vendor/returns/{id}/received` | 🏪 staff | `{ restock: true }` → refund + inventory movement |

### 13.6 Bookings (job cards)
| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/vendor/bookings` | 🏪 staff | `?date=2026-12-01&status=` |
| GET | `/vendor/bookings/{id}` | 🏪 staff | |
| POST | `/vendor/bookings/{id}/confirm` | 🏪 staff | |
| POST | `/vendor/bookings/{id}/reject` | 🏪 staff | `{ reason }` |
| POST | `/vendor/bookings/{id}/check-in` | 🏪 staff | `{ odometerKm, photos: [publicId] }` |
| POST | `/vendor/bookings/{id}/estimates` | 🏪 staff | New version |
| POST | `/vendor/bookings/{id}/start` | 🏪 staff | Only when no estimate is needed |
| POST | `/vendor/bookings/{id}/ready` | 🏪 staff | `{ afterPhotos: [publicId] }` → customer is asked to pay the balance |
| POST | `/vendor/bookings/{id}/offline-payment` | 🏪 manager | `{ method: "cash"\|"upi_direct", amountPaise }` → completes; commission is debited from the ledger |
| POST | `/vendor/bookings/{id}/no-show` | 🏪 staff | |
| POST | `/vendor/bookings/{id}/attachments` | 🏪 staff | |

```json
// POST /vendor/bookings/{id}/estimates
{
  "items": [
    { "kind": "service", "serviceId": "s1…", "description": "AC Gas Refill (R134a)", "quantity": 1, "unitPricePaise": 149900, "gstRateBps": 1800, "hsnSacCode": "998714" },
    { "kind": "part", "description": "Front-left stabiliser link", "quantity": 1, "unitPricePaise": 95000, "gstRateBps": 1800, "hsnSacCode": "87088000" },
    { "kind": "labour", "description": "Link replacement labour", "quantity": 1, "unitPricePaise": 55100, "gstRateBps": 1800, "hsnSacCode": "998714" },
    { "kind": "service", "description": "Wheel alignment (recommended)", "quantity": 1, "unitPricePaise": 59100, "gstRateBps": 1800, "isOptional": true }
  ],
  "vendorNote": "Stabiliser link worn out — photos attached",
  "validForHours": 24
}
// 201 { "id": "es1…", "version": 2, "subtotalPaise": 359100, "taxPaise": 64638, "totalPaise": 423738, "status": "pending" }
```
The server computes every total. Client-sent totals are ignored. If the customer declines the optional alignment line, the approved total is ₹3,540 (300000 + 54000 paise), the figure used in the settlement example below.

### 13.7 Dashboard, analytics, earnings, payouts
| Method | Path | Access | Notes |
|---|---|---|---|
| GET | `/vendor/dashboard` | 🏪 staff (money fields need manager) | Home screen in one call |
| GET | `/vendor/analytics?from=&to=&granularity=day\|week\|month` | 🏪 manager | |
| GET | `/vendor/earnings` | 🏪 manager | Balances |
| GET | `/vendor/ledger?cursor=` | 🏪 manager | Statement lines |
| GET | `/vendor/settlements/{orderId\|bookingId}` | 🏪 manager | Per-order breakdown |
| POST | `/vendor/payouts` | 🏪 owner · **Idempotency-Key** | `{ amountPaise, bankAccountId }` |
| GET | `/vendor/payouts` | 🏪 manager | |
| GET | `/vendor/reviews` | 🏪 staff | `?rating=&replied=false` |
| POST | `/vendor/reviews/{id}/reply` | 🏪 manager | `{ reply }`, editable for 7 days |

```json
// GET /vendor/dashboard
{
  "vendor": { "id": "b1…", "businessName": "Shree Auto Parts & Service", "status": "approved", "isAcceptingOrders": true,
              "rating": { "avg": 4.4, "count": 128 } },
  "today": {
    "date": "2026-12-01",
    "newOrders": 3, "ordersToDispatch": 5,
    "bookings": { "total": 9, "requested": 2, "inProgress": 3, "completed": 4 },
    "revenuePaise": 1849500
  },
  "actionItems": [
    { "type": "order_pending_acceptance", "id": "e7…", "label": "ORD-261201-000123 · 2 items", "dueAt": "2026-12-01T08:30:00Z" },
    { "type": "booking_estimate_rejected", "id": "a3…", "label": "BKG-261201-000044 · Creta" },
    { "type": "low_stock", "id": "1b4e…", "label": "Front Brake Pad Set · 2 left" }
  ],
  "earnings": { "availablePaise": 4523000, "onHoldPaise": 1210000, "payoutInProgress": null },
  "last7Days": [
    { "date": "2026-11-25", "revenuePaise": 1520000, "orders": 6, "bookings": 8, "profileViews": 210 }
  ],
  "unreadChats": 4
}

// GET /vendor/analytics?from=2026-11-01&to=2026-11-30&granularity=week
{
  "totals": { "gmvPaise": 41230000, "orders": 96, "bookings": 141, "profileViews": 5210, "listingViews": 14820,
              "searchImpressions": 60210, "callClicks": 312, "chatStarts": 188,
              "conversionRate": 0.045, "avgOrderValuePaise": 175000, "repeatCustomerRate": 0.31,
              "rating": { "avg": 4.4, "newReviews": 23 } },
  "series": [ { "periodStart": "2026-11-02", "gmvPaise": 9120000, "orders": 21, "bookings": 30, "profileViews": 1180 } ],
  "topProducts": [ { "productId": "1b4e…", "name": "Front Brake Pad Set", "unitsSold": 34, "revenuePaise": 5096600 } ],
  "topServices": [ { "serviceId": "s1…", "name": "AC Gas Refill (R134a)", "bookings": 41, "revenuePaise": 6145900 } ]
}

// GET /vendor/settlements/e1…   (the ₹2,998 brake-pad order)
{
  "orderNumber": "ORD-261125-000001",
  "grossPaise": 299800,                // what the customer paid (GST-inclusive)
  "taxableValuePaise": 254068,
  "commission": { "rateBps": 800, "feePaise": 23984, "gstOnFeePaise": 4317 },
  "tcsPaise": 2541,                    // GST s.52 — 1% of taxable value, claimable in your GSTR-2B
  "tdsPaise": 254,                     // Income-tax s.194-O — 0.1%, shows in your Form 26AS
  "netPayablePaise": 268704,
  "availableAt": "2026-12-03T12:30:00Z"   // delivered + 7-day return window
}
```

---

## 14. Admin API (`/admin/*`, admin app only)

Role matrix:

| Area | super_admin | operations | finance | support | moderator |
|---|:-:|:-:|:-:|:-:|:-:|
| KPIs dashboard | ✔ | ✔ | ✔ | ✔ | – |
| Vendor approvals / suspend | ✔ | ✔ | – | read | – |
| Catalog & vehicle master | ✔ | ✔ | – | – | – |
| Commission rules | ✔ | – | ✔ | – | – |
| Orders / bookings (view, cancel) | ✔ | ✔ | read | ✔ | – |
| Refunds | ✔ | – | ✔ | create ≤ ₹2,000 | – |
| Payouts | ✔ | – | ✔ | – | – |
| Disputes | ✔ | ✔ | ✔ | ✔ | – |
| Review & media moderation | ✔ | ✔ | – | ✔ | ✔ |
| Users (suspend) | ✔ | ✔ | – | read | – |
| Audit log | ✔ | – | ✔ | – | – |

| Method | Path | Notes |
|---|---|---|
| GET | `/admin/kpis?from=&to=&city=` | GMV, net revenue, orders, bookings, DAU/MAU, new users, repeat rate, take rate, top vendors, refund rate |
| GET | `/admin/vendors?status=pending_review&domain=&city=&q=&page=` | Approval queue (oldest first) |
| GET | `/admin/vendors/{id}` | Full profile + documents (5-minute signed URLs) + stats + audit history |
| PATCH | `/admin/vendor-documents/{id}` | `{ status: "verified"\|"rejected", reviewNote }` |
| POST | `/admin/vendors/{id}/approve` | Needs all required docs `verified` and bank account verified; creates the Razorpay Route linked account |
| POST | `/admin/vendors/{id}/reject` | `{ reason }` (shown to the vendor) |
| POST | `/admin/vendors/{id}/suspend` / `/reinstate` | `{ reason }`; suspend hides listings and blocks new orders |
| PATCH | `/admin/vendors/{id}/commission` | `{ commissionBpsOverride: 600 \| null }` |
| CRUD | `/admin/categories`, `/admin/subcategories`, `/admin/brands`, `/admin/vehicle-makes`, `/admin/vehicle-models`, `/admin/vehicle-variants` | Uses `nameI18n` |
| GET / POST | `/admin/commission-rules` | New rule closes the previous one (`effective_to`) |
| GET | `/admin/orders`, `/admin/bookings`, `/admin/payments`, `/admin/refunds` | Filters: status, vendor, customer phone, date, amount |
| GET | `/admin/orders/{id}`, `/admin/bookings/{id}` | With payment, refunds, history, chat link |
| POST | `/admin/orders/{id}/cancel`, `/admin/bookings/{id}/cancel` | `{ reason, refund: true }` |
| POST | `/admin/refunds` · **Idempotency-Key** | `{ orderId\|bookingId, amountPaise, destination: "source"\|"wallet", reason, disputeId? }` |
| GET | `/admin/payouts?status=requested` | |
| POST | `/admin/payouts/{id}/approve` / `/reject` | Approve → Razorpay transfer/payout |
| POST | `/admin/payouts/{id}/mark-paid` | `{ utr }`, manual NEFT fallback |
| GET | `/admin/disputes?status=&assignee=me&overdue=true` | SLA-sorted queue |
| GET | `/admin/disputes/{id}` | Includes internal notes, order/booking, chat transcript |
| POST | `/admin/disputes/{id}/assign` | `{ adminId }` |
| POST | `/admin/disputes/{id}/messages` | `{ body, isInternal }` |
| POST | `/admin/disputes/{id}/resolve` | See below |
| GET | `/admin/moderation/reviews?status=pending\|reported` | |
| POST | `/admin/reviews/{id}/publish` / `/hide` / `/remove` | `{ note }` |
| GET | `/admin/moderation/media?status=pending` | Review photos, product images |
| POST | `/admin/media/{type}/{id}/approve` / `/reject` | |
| POST | `/admin/products/{id}/block` / `/unblock`, `/admin/services/{id}/block` | `{ reason }` |
| GET | `/admin/users?phone=&q=` · GET `/admin/users/{id}` | |
| POST | `/admin/users/{id}/suspend` / `/reinstate` | Revokes all sessions |
| GET | `/admin/audit-logs?entityType=&entityId=&actorId=` | |

```json
// POST /admin/vendors/{id}/approve
{ "note": "All docs verified on call" }
// 200 { "id": "b1…", "status": "approved", "reviewedAt": "…", "razorpayLinkedAccountId": "acc_P…" }
// 422 { "error": { "code": "VALIDATION_FAILED", "details": { "missing": ["gst_certificate"] } } }

// POST /admin/disputes/{id}/resolve
{
  "outcome": "resolved_partial_refund",       // resolved_refund | resolved_partial_refund | resolved_no_action
  "refund": { "amountPaise": 74950, "destination": "source" },
  "chargeVendor": true,                        // refund is reversed from the vendor's ledger
  "resolutionNote": "Wrong part supplied; customer keeps item, 50% refund agreed."
}
// 200 { "status": "resolved_partial_refund", "refundId": "rf…", "resolvedAt": "…" }

// GET /admin/kpis?from=2026-11-01&to=2026-11-30
{
  "gmvPaise": 912300000, "netRevenuePaise": 89400000, "takeRate": 0.098,
  "orders": 3120, "bookings": 4410, "aovPaise": 121000,
  "users": { "new": 5210, "dau": 2100, "mau": 18400, "repeatRate30d": 0.27 },
  "refundRate": 0.021, "disputeRate": 0.004,
  "topVendors": [ { "vendorId": "b1…", "businessName": "Shree Auto Parts & Service", "gmvPaise": 41230000, "rating": 4.4 } ],
  "byDomain": { "parts": { "gmvPaise": 401000000 }, "service": { "gmvPaise": 388000000 }, "decor": { "gmvPaise": 123300000 } }
}
```
Every admin `POST`/`PATCH`/`DELETE` writes an `audit_logs` row (before/after JSON, IP, request id).

---

## 15. Push notification catalog

| `type` | To | Deep link |
|---|---|---|
| `order.placed` | vendor | `/orders/{id}` (high priority, sound) |
| `order.accepted` · `order.dispatched` · `order.out_for_delivery` · `order.delivered` | customer | `/orders/{id}` |
| `order.rejected` · `order.cancelled` | customer / vendor | `/orders/{id}` |
| `order.auto_reject_warning` | vendor (1 h before auto-reject) | `/orders/{id}` |
| `booking.requested` | vendor | `/bookings/{id}` |
| `booking.confirmed` · `booking.reminder` (2 h before) | customer | `/bookings/{id}` |
| `booking.estimate_shared` | customer | `/bookings/{id}/estimate` |
| `booking.estimate_approved` · `booking.estimate_rejected` | vendor | `/bookings/{id}` |
| `booking.ready` | customer | `/bookings/{id}/pay` |
| `return.requested` | vendor | `/returns/{id}` |
| `return.approved` · `refund.processed` | customer | `/orders/{id}` |
| `chat.message` | both | `/chat/{conversationId}` (collapsed per conversation) |
| `review.received` | vendor | `/reviews` |
| `vendor.approved` · `vendor.rejected` · `document.rejected` | vendor | `/onboarding` |
| `payout.paid` · `payout.failed` | vendor | `/earnings/payouts/{id}` |
| `dispute.updated` | both | `/disputes/{id}` |
| `stock.low` | vendor (daily digest) | `/inventory?lowStock=true` |

FCM payload: `notification: { title, body }` localised to the device locale, plus `data: { type, route, entityId }`. iOS uses `apns-priority: 10` for `order.placed` and `booking.requested`.

---

## 16. Endpoint count by module (for planning)

| Module | Endpoints | MVP |
|---|---:|:-:|
| Auth + Me | 26 | ✔ |
| Catalog | 6 | ✔ |
| Products + discovery | 11 | ✔ |
| Cart / checkout / orders / returns | 14 | ✔ |
| Payments + webhook | 4 | ✔ |
| Bookings + media | 10 | ✔ |
| Reviews / chat / disputes | 14 | ✔ (disputes basic) |
| Vendor | 72 | ✔ (analytics basic) |
| Admin | 67 | ✔ approvals, catalog, refunds, payouts, disputes, moderation · ⏭ advanced KPIs |
| **Total** | **≈225** (each method + path pair counted once) | |

The detailed MVP vs Phase-2 cut comes with deliverable 10. Endpoints marked here are the ones the MVP screens need.
