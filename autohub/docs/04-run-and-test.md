# Run & test AutoHub locally

Everything runs on your own computer: Postgres, the API, and both Flutter apps (Android emulator, iOS
simulator, or your phone on the same Wi-Fi). No Razorpay account and no SMS provider needed. The API runs in
**test mode**: OTP codes are shown in the app, and payments are simulated.

## 0. Install once

| Tool | Version | Notes |
|---|---|---|
| Node.js | 22 LTS | https://nodejs.org |
| Docker Desktop | any recent | runs Postgres + Redis. (Or install PostgreSQL 16 + PostGIS yourself.) |
| Flutter | 3.50+ stable | https://docs.flutter.dev/get-started/install, then run `flutter doctor` |
| Android Studio | latest | Android SDK + an emulator (Pixel, API 34+) |
| Xcode (Mac only) | 16+ | for the iOS simulator / iPhone. No Mac? See "iOS without a Mac" below |

## 1. Database

From the `autohub/` folder:

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis
```

## 2. API

```bash
cd backend
```

```bash
npm install
```

```bash
cp .env.example .env
```

The defaults in `.env` already point at the Docker database and use test mode. Create the tables and load
reference and demo data:

```bash
npm run db:setup
```

```bash
npm run dev
```

You should see `API listening on http://localhost:3000/v1`. Open **http://localhost:3000/docs** for Swagger UI:
every endpoint can be tried from the browser. Click **Authorize** to paste an access token, and set the
`X-Client-App` header (and `X-Vendor-Id` for vendor routes).

Run the backend test suite (it creates and resets its own `autohub_e2e` database):

```bash
TEST_DATABASE_URL=postgres://autohub:autohub@localhost:5432/autohub_e2e?sslmode=disable npm test
```

## 3. Apps

```bash
cd mobile
```

```bash
flutter pub get
```

**Customer app** (Android emulator reaches your PC at `10.0.2.2`, which is the default):

```bash
cd apps/customer_app && flutter run
```

**Partner (vendor) app**:

```bash
cd apps/vendor_app && flutter run
```

**On a real phone (same Wi-Fi as your PC)**: find your PC's IP (e.g. `192.168.1.20`), then either pass it at
build time:

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:3000/v1
```

or tap the **server icon** on the login screen and type `http://192.168.1.20:3000`.

Flutter tests (unit + widget, no server needed):

```bash
cd mobile/packages/autohub_core && flutter test
```

```bash
cd mobile/apps/customer_app && flutter test
```

```bash
cd mobile/apps/vendor_app && flutter test
```

Live client-against-server check (API must be running):

```bash
cd mobile/packages/autohub_core && AUTOHUB_API=http://localhost:3000/v1 flutter test test/live_backend_test.dart
```

## 4. Demo accounts

The login screen shows the OTP as a tappable "Test mode code" chip.

| App | Phone (type without +91) | Who |
|---|---|---|
| Customer | `9000000001` | Rahul Patil: Swift 2021 (MH12AB1234) + Creta 2022 |
| Partner | `9000000002` | Shree Auto Parts & Service (parts + workshop), Kothrud |
| Partner | `9000000004` | GlossUp Car Decor, Baner |
| Partner | `9000000005` | Pitstop Car Care, Viman Nagar |

Any other number creates a new customer account.

## 5. Things to try

1. **Customer → Parts:** search `brak` (prefix match) or a part number such as `16510M68K00`. Switch between
   *Swift* and *Creta*: the Creta brake pads only appear for the Creta. Turn on airplane mode and reopen a
   search you did before: it loads from the offline cache with a banner.
2. **Customer → Services → Shree → Book:** pick *Basic Service* + *Suspension Noise Inspection*, choose a
   slot, confirm. The test payment sheet pays the ₹200 advance.
3. **Partner app (9000000002):** the booking shows on the dashboard. Open it, then *Confirm* → *Check in* →
   *Send estimate*: add a part line and mark a line *optional*.
4. **Customer → Bookings:** the estimate appears. Untick the optional line and *Approve*.
5. **Partner:** *Mark ready*. **Customer:** *Pay* the balance. The booking completes, and the partner job card
   shows the settlement (commission, GST on commission, TCS, TDS, payout).
6. **Hindi / Marathi:** language icon on the login screen, or Account → Language.

## 6. Switching on real services

| What | Change in `backend/.env` |
|---|---|
| Real SMS | `SMS_DRIVER=msg91`, `MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID` (DLT-approved template), `OTP_DEV_ECHO=false` |
| Razorpay test keys | `RAZORPAY_MODE=live`, `RAZORPAY_KEY_ID=rzp_test_…`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`. The apps then open the real Razorpay sheet (test cards / `success@razorpay` UPI) |
| Redis rate limits | `REDIS_URL=redis://localhost:6379` (the compose file starts Redis; required in production) |

`NODE_ENV=production` refuses to start with test-mode settings still enabled.

## 7. Building installable apps

**Android APK** (install directly on phones for testing):

```bash
cd mobile/apps/customer_app && flutter build apk --release --split-per-abi --dart-define=API_URL=http://192.168.1.20:3000/v1 --android-project-arg=autohub.allowCleartext=true
```

The APKs are in `build/app/outputs/flutter-apk/`; `app-armeabi-v7a-release.apk` suits most budget phones.
`autohub.allowCleartext=true` permits plain HTTP to your PC; leave it off for builds that talk to the HTTPS
production API.

**iOS on a Mac:** open `mobile/apps/customer_app/ios/Runner.xcworkspace` in Xcode, pick your Team under
*Signing & Capabilities*, then:

```bash
flutter run --release
```

**iOS without a Mac:** `codemagic.yaml` at the root of the My-Projects repo builds both apps on Codemagic's Macs and uploads
them to TestFlight. You need an Apple Developer account ($99/year) and an App Store Connect API key, added to
Codemagic as an integration named `autohub_asc`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App shows "No internet connection" on emulator | API not running, or you changed the server address. Android emulator must use `10.0.2.2`, iOS simulator `localhost` |
| Phone can't reach the API | Same Wi-Fi? PC firewall allowing port 3000? Use the PC's LAN IP, not `localhost` |
| `RATE_LIMITED` on login | One OTP per number per 30 s and 5 per hour. Wait, or restart the API (limits are in memory without Redis) |
| No slots shown | Slots are generated for 14 days when the API starts; Shree is closed on Sundays, GlossUp on Mondays |
| `npm test` refuses to run | The test database name must end in `_e2e` or `_test`. This protects your dev data |
