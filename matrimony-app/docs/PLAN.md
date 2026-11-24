# Matrimony App: Decisions & Plan

Agreed on 24 Nov 2026. Change this file when a decision changes.

## Decisions
| Topic | Decision |
|---|---|
| Market | India-wide. Users pick religion → community → sub-community at registration |
| Who registers | Self, parent, sibling, relative or friend. If it isn't the candidate, the profile stays hidden until the candidate confirms with an OTP on their own phone |
| Accounts | One account = one profile (MVP) |
| Launch | **Web beta 1 Jan 2027**; Flutter app Feb–Mar 2027 |
| Language | English first; i18n-ready |
| Verification | Mobile OTP is mandatory. Aadhaar is **optional**, done only through a licensed provider (DigiLocker / IDfy / Digio), with PAN, DL, voter ID or passport as alternatives. Store the masked number only |
| Horoscope | Optional fields. Guna-milan later |
| Monetization | Free users browse and send 5 interests a day. Premium plans of 3, 6 or 12 months unlock chat plus contact-view credits. Razorpay |
| Chat | Only after an interest is accepted **and** at least one side is premium. Text only |
| Stack | FastAPI · SQLAlchemy 2 · Alembic · PostgreSQL 16 · Redis 7 · Celery · React 19 + Vite · Tailwind · Flutter · Cloudflare R2 · MSG91 · Razorpay · SES · FCM · Sentry |
| Hosting | DigitalOcean Bangalore (droplet + managed Postgres), Cloudflare Pages for web. About ₹4–5k/month fixed |
| Web framework | React + Vite SPA (profiles must not be indexed). SEO landing pages later as static pages or a separate small site |

## Start now (long lead times)
- [ ] TRAI DLT registration (through MSG91): entity, sender ID, OTP template. 3–7 days
- [ ] Razorpay business KYC + activation. Needs live Terms, Privacy and Refund pages. 3–10 days
- [ ] KYC vendor contract for Aadhaar/ID. 2–4 weeks
- [ ] Lawyer review of Terms, Privacy, Refund and Safety pages (₹10–25k)
- [ ] Appoint and publish a Grievance Officer (IT Rules 2021)
- [ ] GST registration (18% on subscriptions) — ask a CA

## Legal & safety must-haves
- DPDP Act 2023 + Rules 2025: consent log, access/correct/erase, breach notification, data retention limits
- IT Intermediary Rules 2021: Grievance Officer, acknowledge in 24h, resolve in 15 days, remove intimate/impersonation images within 24h
- Aadhaar Act s.29: never store the full Aadhaar number
- Dowry Prohibition Act: block dowry terms; "dowry" is a report reason
- Minimum age: 21 for men, 18 for women
- Scam warnings in chat ("never send money")

## Security rules (keep these true)
- Phone and email: HMAC hash for lookups, AES-GCM ciphertext for display. Never plaintext, never in logs
- Contact details are returned **only** through a contact unlock or the profile's privacy setting
- Users only ever see `public_id`, never internal UUIDs
- Photos: private bucket, 10-minute signed URLs, EXIF stripped, blurred copies made on the server, every photo moderated
- OTP: 6 digits, 5-minute expiry, 3 attempts, 30s resend cooldown, 3 per hour per phone, 10 per hour per IP
- JWT 15 min; refresh token 30 days, rotated, reuse ⇒ the whole family is revoked
- Admins: TOTP 2FA, PII masked by default, every action written to `admin_actions`
- Auto-hide a profile after 3 reports from different users, pending moderator review

## Roadmap
| Week | Dates | Deliverable |
|---|---|---|
| 1 | Nov 24–30 | ✅ Scaffold, schema, OTP auth, profile create/update, master data, login page |
| 2 | Dec 1–7 | Registration form (web), photo upload pipeline (R2 + Celery), partner preferences |
| 3 | Dec 8–14 | Search + two-way matching, profile view with privacy rules, interests, shortlist, block |
| 4 | Dec 15–21 | WebSocket chat, reports, Razorpay plans + webhook, contact unlock |
| 5 | Dec 22–28 | Admin dashboard, DPDP export/delete, security pass, seed data, closed beta |
| Freeze | Dec 29–31 | Bug fixes, production deploy, backup restore test |
| 🚀 | **Jan 1** | **Public web beta** |
| 6–7 | Jan 2–15 | ID verification, daily matches, email notifications, fake-profile risk score |
| 8–15 | Jan 15–Mar 15 | Flutter app (Android, then iOS), push notifications |
| Later | Mar+ | Guna-milan, SEO pages, Hindi, selfie liveness |

If anything slips, cut admin features to the minimum (photo queue + ban). **Never cut** chat safety or the legal pages.

## Known TODOs in the scaffold
- Web keeps the refresh token in `localStorage`. Move it to an httpOnly cookie before launch
- A deleted account's phone number can't re-register until the purge job removes it (purge job not built yet)
- `Msg91Sms` payload must be checked against your MSG91 account's Flow API docs once DLT is approved
