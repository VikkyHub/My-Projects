# Matrimony App

Web-first matrimony platform for India. FastAPI backend, React web app, Flutter mobile app (Feb–Mar 2027).

| Folder | What | Status |
|---|---|---|
| `backend/` | FastAPI + PostgreSQL + Redis API | Auth, profiles, photos, matching, interests, chat, admin ✅ |
| `web/` | React 19 + Vite + Tailwind | Member app + admin panel (`/admin`) ✅ |
| `mobile/` | Flutter app | Starts mid-January |
| `docs/` | Decisions, roadmap, schema | |

Read `docs/PLAN.md` for the product decisions, security rules and roadmap.

---

## Setup on Windows (one time)

Install these first:
1. **Git**: https://git-scm.com/download/win
2. **Python 3.12**: https://www.python.org/downloads/ (tick *Add python.exe to PATH*)
3. **Node.js 22 LTS**: https://nodejs.org
4. **Docker Desktop**: https://www.docker.com/products/docker-desktop/ (runs Postgres and Redis for you)
5. **uv** (fast Python package manager), in PowerShell:
   ```powershell
   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
   ```

Get the code:
```powershell
cd D:\WorkSpace\Vikas
git clone https://github.com/VikkyHub/My-Projects.git
cd My-Projects\matrimony-app
```

## Run it locally

**1. Start Postgres and Redis** (keep Docker Desktop open):
```powershell
docker compose up -d db redis
```

**2. Backend** (new PowerShell window):
```powershell
cd backend
uv venv
.venv\Scripts\activate
uv pip install -e ".[dev]"
copy .env.example .env
alembic upgrade head
python -m scripts.seed_master
python -m scripts.seed_profiles
uvicorn app.main:app --reload
```
- API docs: http://localhost:8000/docs
- In dev, OTPs are **not sent by SMS**, and with the default `.env` every OTP is **123456**.
- `seed_profiles` adds 60 sample members so Matches/Interests/Messages have people in them:
  brides **9000000001–9000000030**, grooms **9000000031–9000000060** (OTP 123456).
  Every 3rd one is Premium, so chat works with them.
- `DEV_AUTO_APPROVE=true` makes new profiles and photos go live immediately (no admin panel yet).
- Uploaded photos are stored in `backend/media/` in dev (git-ignored).

**3. Web** (another PowerShell window):
```powershell
cd web
copy .env.example .env
npm install
npm run dev
```
Open http://localhost:5173 and log in with any Indian mobile number. Take the OTP from the backend window.

**4. Tests** (needs `docker compose up -d db redis`; the test database is created automatically on first start):
```powershell
cd backend
pytest
```

## Help chat, translation & conduct rules

**Help** (in the member menu): an assistant answers common questions instantly (OTP, photos,
review, matches, interests, chat, premium, safety, blocking…, English + Hinglish). Unknown
questions, "Talk to a person", a 👎 on an answer, payments/refunds, account deletion, photos and
voice notes, and urgent words (threats, blackmail…) go to the **Support inbox** in the admin panel.
Staff replies appear in the member's chat instantly. Assistant topics live in
`backend/app/services/helpbot.py` — add an `Intent` to teach it something new.

**Translate**: any received message (help chat, member chat, support inbox) can be translated
into 11 languages. In Chrome it runs **on-device** (built-in Translator API — the text never
leaves the computer). Other browsers fall back to the server only if
`TRANSLATE_PROVIDER=google` + `GOOGLE_TRANSLATE_API_KEY` are set.

**Conduct rules**: vulgar/abusive language (English, Hinglish, Hindi/Telugu/Tamil/Kannada…, incl.
disguised spellings like `f*ck`, `f.u.c.k`) is blocked in member chat, help chat, interest notes
and "About me". Each block is a recorded violation (the text itself is never stored);
**3 within 7 days mute member chat for 24 hours** (help chat stays open). Tune with
`CONDUCT_MUTE_AFTER`, `CONDUCT_WINDOW_DAYS`, `CONDUCT_MUTE_HOURS`; word lists are in
`backend/app/services/conduct.py`.

## Admin panel

Staff use a **separate login** at **http://localhost:5173/admin/login**: work email + password +
a 6-digit code from Google/Microsoft Authenticator. Members can never reach it with their phone OTP.

**Create your first admin** (backend window, venv active):
```powershell
python -m scripts.create_admin --email you@example.com --name "Your Name"
```
Sign in, scan the QR code with your authenticator app, done. Invite more staff from **Staff** in the panel.

**Fill the queues with sample work** (4 profiles + photos to review, 3 reports):
```powershell
python -m scripts.seed_moderation
```
To see real moderation behaviour (new profiles/photos waiting for approval), set
`DEV_AUTO_APPROVE=false` in `backend\.env` and restart the backend.

| | Moderator | Admin |
|---|---|---|
| Review profiles & photos, resolve reports | ✅ | ✅ |
| Warn / suspend members, reveal phone (logged) | ✅ | ✅ |
| Ban, lift bans | — | ✅ |
| Invite/disable staff, reset their login | — | ✅ |
| Audit log, App logs | — | ✅ |

**App logs** (admins only): sign-ins (members and staff), failed attempts and lockouts,
security events (stolen-token detection, flagged chat, duplicate photos, auto-hidden profiles),
activity, and server errors with a request ID. Phone numbers are masked, chat text is never
logged, and entries are deleted after 90 days (`APP_LOG_RETENTION_DAYS`). Every API response
carries an `X-Request-ID` header you can search for.

Staff sessions end after 30 minutes idle or 8 hours, and close with the browser. 5 wrong passwords
lock the account for 15 minutes. Every action is recorded in the audit log.

## API so far
Full, live documentation: **http://localhost:8000/docs**

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/otp/send`, `/auth/otp/verify`, `/auth/refresh`, `/auth/logout`, `/auth/ws-ticket` |
| Master data | `GET /master/religions`, `communities`, `sub-communities`, `mother-tongues`, `cities`, `states`, `education-levels`, `occupations` |
| My profile | `POST /profiles`, `GET/PATCH /profiles/me`, candidate consent `send/verify`, `GET/PUT /profiles/me/preferences` |
| Photos | `GET/POST /profiles/me/photos`, `DELETE /profiles/me/photos/{id}`, `POST …/{id}/primary`, `GET/PUT /profiles/me/photo-settings` |
| Matches | `GET /matches?mode=recommended\|all&…filters&cursor=`, `GET /profiles/{public_id}` |
| Shortlist / safety | `GET /shortlist`, `PUT/DELETE /shortlist/{public_id}`, `POST /profiles/{public_id}/block`, `POST /profiles/{public_id}/report` |
| Interests | `POST /interests`, `GET /interests?box=received\|sent\|accepted`, `POST /interests/{id}/accept\|decline\|withdraw`, `GET /interests/counts` |
| Help chat | `GET /support`, `POST /support/messages`, `POST /support/attachments` (photo / voice), `POST /support/escalate`, `POST /support/feedback`, `POST /support/close`, `POST /translate` |
| Chat | `GET /conversations`, `GET/POST /conversations/{id}/messages`, `POST /conversations/{id}/read`, `WS /ws?ticket=` |
| Staff auth | `POST /admin/auth/login`, `POST /admin/auth/verify`, `GET /admin/auth/me` |
| Admin | `GET /admin/stats`, `GET /admin/profiles`, `GET /admin/profiles/{id}`, `POST …/moderate`, `POST …/reveal-phone`, `GET /admin/photos`, `POST /admin/photos/{id}/moderate`, `GET /admin/reports`, `POST /admin/reports/{id}/resolve`, `GET /admin/audit`, `GET /admin/logs`, `GET /admin/logs/summary`, `GET /admin/support`, `GET /admin/support/{id}`, `POST /admin/support/{id}/reply\|close`, `GET/POST /admin/staff`, `POST /admin/staff/{id}/disable\|enable\|reset` |

## Rules already enforced in code
- Phone numbers are stored **HMAC-hashed + AES-GCM encrypted**, never as plain text.
- Minimum age is 21 for men and 18 for women. Gender and date of birth can't be edited after creation.
- A profile created by a relative stays **hidden** until the candidate confirms with an OTP on their own phone.
- One profile per candidate: a parent can't create a second profile for someone who already has one.
- "About me" rejects phone numbers, emails, links and dowry terms.
- The community must belong to the chosen religion. Changing the religion clears the community.
- Every consent (terms, privacy, candidate consent) is logged with its version and IP for DPDP.
- **Matching is two-way**: recommended profiles fit your preferences *and* you fit theirs.
- Free members see only last-name initials, and get 5 interests a day (Premium: 50).
- **Chat opens only after an interest is accepted and one side is Premium.** Messages mentioning
  money, phone numbers, UPI IDs or links are flagged with a warning; dowry talk is rejected.
- Block hides both people from each other everywhere and closes their chat. 3 reports from
  different members auto-hide a profile pending review.
- Photos: re-encoded to WebP (EXIF/GPS removed), served only via expiring signed links,
  blurred for viewers your privacy setting excludes; duplicates of another member's photo are held for review.

## Database changes
Edit models in `backend/app/models/`, then:
```powershell
alembic revision --autogenerate -m "describe change"
alembic upgrade head
```
`docs/schema.sql` is a readable dump of the current schema.
