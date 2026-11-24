# Matrimony App

Web-first matrimony platform for India. FastAPI backend, React web app, Flutter mobile app (Feb–Mar 2027).

| Folder | What | Status |
|---|---|---|
| `backend/` | FastAPI + PostgreSQL + Redis API | Auth, profiles, master data ✅ |
| `web/` | React 19 + Vite + Tailwind | OTP login ✅ |
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
uvicorn app.main:app --reload
```
- API docs: http://localhost:8000/docs
- In dev, OTPs are **not sent by SMS**. They're printed in this window, like
  `DEV OTP (not sent) code=123456`.

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

## API so far

| Method | Path | What it does |
|---|---|---|
| POST | `/api/v1/auth/otp/send` | Send login OTP (rate-limited: 30s cooldown, 3/hour per phone, 10/hour per IP) |
| POST | `/api/v1/auth/otp/verify` | Verify OTP; creates account on first login; returns access + refresh tokens |
| POST | `/api/v1/auth/refresh` | Rotate refresh token (reusing an old one logs out every session in that family) |
| POST | `/api/v1/auth/logout` | Revoke refresh token |
| GET | `/api/v1/master/religions` | Registration dropdowns… |
| GET | `/api/v1/master/communities?religion_id=` | …community for that religion |
| GET | `/api/v1/master/sub-communities?community_id=` | …sub-community |
| GET | `/api/v1/master/mother-tongues` | |
| POST | `/api/v1/profiles` | Create profile (self / parent / sibling / relative / friend) |
| GET | `/api/v1/profiles/me` | My profile |
| PATCH | `/api/v1/profiles/me` | Update basics + family / career / horoscope sections |
| POST | `/api/v1/profiles/me/candidate-consent/send` | OTP to the **candidate's** phone when a relative created the profile |
| POST | `/api/v1/profiles/me/candidate-consent/verify` | Candidate confirms → profile moves from `draft` to `pending_review` |

## Rules already enforced in code
- Phone numbers are stored **HMAC-hashed + AES-GCM encrypted**, never as plain text.
- Minimum age is 21 for men and 18 for women. Gender and date of birth can't be edited after creation.
- A profile created by a relative stays **hidden** until the candidate confirms with an OTP on their own phone.
- One profile per candidate: a parent can't create a second profile for someone who already has one.
- "About me" rejects phone numbers, emails, links and dowry terms.
- The community must belong to the chosen religion. Changing the religion clears the community.
- Every consent (terms, privacy, candidate consent) is logged with its version and IP for DPDP.

## Database changes
Edit models in `backend/app/models/`, then:
```powershell
alembic revision --autogenerate -m "describe change"
alembic upgrade head
```
`docs/schema.sql` is a readable dump of the current schema.
