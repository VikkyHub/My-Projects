import pytest
from sqlalchemy import select, update

from app.core.security import decrypt, encrypt, hash_password, hmac_hash, totp_now
from app.db.session import SessionLocal
from app.models import AdminAction, Photo, User
from tests.conftest import auth
from tests.test_social import jpeg, member  # noqa: F401  (fixture)

PW = "StaffPass123"


async def make_staff(email="mod@example.com", role="moderator", must_change=False, pw=PW):
    async with SessionLocal() as db:
        u = User(
            email_hash=hmac_hash(email),
            email_enc=encrypt(email),
            name=email.split("@")[0],
            role=role,
            password_hash=hash_password(pw),
            must_change_password=must_change,
        )
        db.add(u)
        await db.commit()
        return u.id


async def secret_of(uid) -> str:
    async with SessionLocal() as db:
        u = await db.get(User, uid)
        return decrypt(u.totp_secret_enc)


@pytest.fixture
def staff_login(client):
    async def _login(email="mod@example.com", role="moderator"):
        uid = await make_staff(email, role)
        r = await client.post("/admin/auth/login", json={"email": email, "password": PW})
        assert r.status_code == 200, r.text
        assert r.json()["step"] == "enroll"
        code = totp_now(await secret_of(uid))
        r = await client.post(
            "/admin/auth/verify", json={"ticket": r.json()["ticket"], "code": code}
        )
        assert r.status_code == 200, r.text
        return r.json()

    return _login


async def test_staff_login_enroll_then_totp(client):
    uid = await make_staff()
    r = await client.post("/admin/auth/login", json={"email": "MOD@example.com", "password": PW})
    body = r.json()
    assert body["step"] == "enroll" and body["otpauth_uri"].startswith("otpauth://totp/")
    bad = await client.post("/admin/auth/verify", json={"ticket": body["ticket"], "code": "000000"})
    assert bad.status_code == 401
    ok = await client.post(
        "/admin/auth/verify",
        json={"ticket": body["ticket"], "code": totp_now(await secret_of(uid))},
    )
    assert ok.status_code == 200 and ok.json()["staff"]["role"] == "moderator"
    # ticket is single use
    again = await client.post(
        "/admin/auth/verify",
        json={"ticket": body["ticket"], "code": totp_now(await secret_of(uid))},
    )
    assert again.status_code == 401
    # second login asks for the code, no new QR
    r = await client.post("/admin/auth/login", json={"email": "mod@example.com", "password": PW})
    assert r.json()["step"] == "totp" and r.json()["otpauth_uri"] is None


async def test_wrong_password_locks_account(client):
    await make_staff()
    for _ in range(5):
        r = await client.post(
            "/admin/auth/login", json={"email": "mod@example.com", "password": "nope"}
        )
        assert r.status_code == 401
    r = await client.post("/admin/auth/login", json={"email": "mod@example.com", "password": PW})
    assert r.status_code == 429 and "locked" in r.json()["detail"]


async def test_unknown_email_same_error(client):
    r = await client.post("/admin/auth/login", json={"email": "nobody@example.com", "password": PW})
    assert r.status_code == 401 and r.json()["detail"] == "Invalid email or password"


async def test_must_change_temporary_password(client):
    uid = await make_staff("new@example.com", must_change=True)
    r = (
        await client.post("/admin/auth/login", json={"email": "new@example.com", "password": PW})
    ).json()
    assert r["must_change_password"] is True
    code = totp_now(await secret_of(uid))
    miss = await client.post("/admin/auth/verify", json={"ticket": r["ticket"], "code": code})
    assert miss.status_code == 422
    weak = await client.post(
        "/admin/auth/verify", json={"ticket": r["ticket"], "code": code, "new_password": "short"}
    )
    assert weak.status_code == 422
    ok = await client.post(
        "/admin/auth/verify",
        json={"ticket": r["ticket"], "code": code, "new_password": "BrandNewPass99"},
    )
    assert ok.status_code == 200, ok.text
    r = await client.post(
        "/admin/auth/login", json={"email": "new@example.com", "password": "BrandNewPass99"}
    )
    assert r.status_code == 200 and r.json()["must_change_password"] is False


async def test_member_token_cannot_use_admin_api(client, member):  # noqa: F811
    t, _ = await member()
    assert (await client.get("/admin/stats", headers=auth(t))).status_code == 401
    # even if a member account were given a staff role, an OTP token isn't a staff token
    async with SessionLocal() as db:
        await db.execute(update(User).where(User.phone_hash.is_not(None)).values(role="admin"))
        await db.commit()
    assert (await client.get("/admin/stats", headers=auth(t))).status_code == 401


async def test_staff_refresh_keeps_admin_scope(client, staff_login):
    t = await staff_login()
    r = await client.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})
    assert r.status_code == 200
    assert (await client.get("/admin/stats", headers=auth(r.json()))).status_code == 200


async def test_review_queue_approve_reject(client, staff_login, login):
    tm = await login("+919811111111")
    await client.post(
        "/profiles",
        json={
            "created_by": "self",
            "first_name": "Neha",
            "gender": "female",
            "dob": "1997-01-01",
            "religion_id": 1,
            "accept_terms": True,
        },
        headers=auth(tm),
    )
    s = await staff_login()
    q = (
        await client.get("/admin/profiles", params={"status": "pending_review"}, headers=auth(s))
    ).json()
    assert q["total"] == 1
    pid = q["items"][0]["public_id"]

    r = await client.post(
        f"/admin/profiles/{pid}/moderate", json={"action": "reject"}, headers=auth(s)
    )
    assert r.status_code == 422  # reason required
    r = await client.post(
        f"/admin/profiles/{pid}/moderate",
        json={"action": "reject", "reason": "Please add your city and a clearer about-me."},
        headers=auth(s),
    )
    assert r.json()["status"] == "rejected"
    me = (await client.get("/profiles/me", headers=auth(tm))).json()
    assert me["status"] == "rejected" and "city" in me["moderation_note"]
    # member edits -> back in the queue
    await client.patch(
        "/profiles/me", json={"about_me": "Updated about me text."}, headers=auth(tm)
    )
    assert (await client.get("/profiles/me", headers=auth(tm))).json()["status"] == "pending_review"
    r = await client.post(
        f"/admin/profiles/{pid}/moderate", json={"action": "approve"}, headers=auth(s)
    )
    assert r.json()["status"] == "active"

    async with SessionLocal() as db:
        actions = [
            a.action
            for a in await db.scalars(select(AdminAction).where(AdminAction.target_id == pid))
        ]
    assert set(actions) == {"reject", "approve"}


async def test_moderator_cannot_ban_admin_can(client, staff_login, member):  # noqa: F811
    t, pid = await member()
    mod = await staff_login("mod@example.com", "moderator")
    r = await client.post(
        f"/admin/profiles/{pid}/moderate",
        json={"action": "ban", "reason": "Scam"},
        headers=auth(mod),
    )
    assert r.status_code == 403
    adm = await staff_login("boss@example.com", "admin")
    r = await client.post(
        f"/admin/profiles/{pid}/moderate",
        json={"action": "ban", "reason": "Scam"},
        headers=auth(adm),
    )
    assert r.status_code == 200
    # banned member is logged out everywhere
    assert (await client.get("/profiles/me", headers=auth(t))).status_code == 401
    assert (
        await client.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})
    ).status_code == 401
    # moderator can't lift a ban; admin can
    r = await client.post(
        f"/admin/profiles/{pid}/moderate", json={"action": "reactivate"}, headers=auth(mod)
    )
    assert r.status_code == 403
    r = await client.post(
        f"/admin/profiles/{pid}/moderate", json={"action": "reactivate"}, headers=auth(adm)
    )
    assert r.json()["account_status"] == "active"


async def test_reveal_phone_requires_reason_and_is_logged(client, staff_login, member):  # noqa: F811
    _, pid = await member()
    s = await staff_login()
    detail = (await client.get(f"/admin/profiles/{pid}", headers=auth(s))).json()
    assert "*" in detail["phone_masked"]
    assert (
        await client.post(
            f"/admin/profiles/{pid}/reveal-phone", json={"reason": ""}, headers=auth(s)
        )
    ).status_code == 422
    r = await client.post(
        f"/admin/profiles/{pid}/reveal-phone",
        json={"reason": "Verifying identity for report"},
        headers=auth(s),
    )
    assert r.json()["phone"].startswith("+91")
    async with SessionLocal() as db:
        a = await db.scalar(select(AdminAction).where(AdminAction.action == "reveal_phone"))
    assert a.reason == "Verifying identity for report"


async def test_photo_queue_and_reports(client, staff_login, member, tmp_path, monkeypatch):  # noqa: F811
    from app.services import storage

    monkeypatch.setattr(storage, "_storage", storage.LocalStorage(str(tmp_path)))
    a, a_pid = await member("female", "Priya")
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    await client.post(
        "/profiles/me/photos", files={"file": ("p.jpg", jpeg(), "image/jpeg")}, headers=auth(a)
    )
    s = await staff_login()
    q = (await client.get("/admin/photos", headers=auth(s))).json()
    assert len(q) == 1 and q[0]["profile"]["public_id"] == a_pid
    r = await client.post(
        f"/admin/photos/{q[0]['id']}/moderate", json={"action": "approve"}, headers=auth(s)
    )
    assert r.json()["status"] == "approved"
    async with SessionLocal() as db:
        assert (await db.scalar(select(Photo.status))) == "approved"

    await client.post(f"/profiles/{a_pid}/report", json={"reason": "fake"}, headers=auth(b))
    reps = (await client.get("/admin/reports", headers=auth(s))).json()
    assert len(reps) == 1 and reps[0]["reported"]["public_id"] == a_pid
    r = await client.post(
        f"/admin/reports/{reps[0]['id']}/resolve",
        json={"action": "warn", "note": "Use real photos"},
        headers=auth(s),
    )
    assert r.json()["status"] == "actioned"
    assert (await client.get("/admin/reports", headers=auth(s))).json() == []
    me = (await client.get("/profiles/me", headers=auth(a))).json()
    assert me["moderation_note"] == "Use real photos"


async def test_staff_management_admin_only(client, staff_login):
    mod = await staff_login("mod@example.com", "moderator")
    assert (await client.get("/admin/staff", headers=auth(mod))).status_code == 403
    assert (await client.get("/admin/audit", headers=auth(mod))).status_code == 403
    adm = await staff_login("boss@example.com", "admin")
    r = await client.post(
        "/admin/staff", json={"email": "new@example.com", "name": "New Mod"}, headers=auth(adm)
    )
    assert r.status_code == 201
    tmp = r.json()["temporary_password"]
    login = await client.post(
        "/admin/auth/login", json={"email": "new@example.com", "password": tmp}
    )
    assert login.json()["must_change_password"] is True
    sid = r.json()["staff"]["id"]
    await client.post(f"/admin/staff/{sid}/disable", headers=auth(adm))
    r = await client.post("/admin/auth/login", json={"email": "new@example.com", "password": tmp})
    assert r.status_code == 403
    audit = (await client.get("/admin/audit", headers=auth(adm))).json()
    assert {"staff_create_moderator", "staff_disable"} <= {a["action"] for a in audit}


async def test_profile_detail_and_stats(client, staff_login, member):  # noqa: F811
    _, pid = await member()
    s = await staff_login()
    st = (await client.get("/admin/stats", headers=auth(s))).json()
    assert st["profiles_live"] == 1 and st["members_total"] >= 1
    d = (await client.get(f"/admin/profiles/{pid}", headers=auth(s))).json()
    assert d["public_id"] == pid and d["photos"] == [] and d["reports"] == []
