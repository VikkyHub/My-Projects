from sqlalchemy import select

from app.core.redis import get_redis
from app.core.security import hmac_hash
from app.db.session import SessionLocal
from app.models import User
from tests.conftest import auth

PHONE = "+919876543210"


async def test_otp_login_creates_user_and_stores_no_plaintext_phone(client, sms, login):
    r = await client.post("/auth/otp/send", json={"phone": "98765 43210"})  # local format ok
    assert r.status_code == 200
    assert r.json()["expires_in"] == 300
    assert PHONE in sms.sent

    r = await client.post("/auth/otp/verify", json={"phone": PHONE, "code": sms.sent[PHONE]})
    body = r.json()
    assert r.status_code == 200
    assert body["is_new_user"] is True and body["has_profile"] is False
    assert body["access_token"] and body["refresh_token"]

    async with SessionLocal() as db:
        user = await db.scalar(select(User).where(User.phone_hash == hmac_hash(PHONE)))
        assert user is not None
        assert PHONE.encode() not in user.phone_enc  # encrypted at rest


async def test_second_login_is_not_new_user(login):
    await login(PHONE)
    again = await login(PHONE)
    assert again["is_new_user"] is False


async def test_invalid_phone_rejected(client, sms):
    r = await client.post("/auth/otp/send", json={"phone": "12345"})
    assert r.status_code == 422


async def test_wrong_otp_counts_attempts_then_locks(client, sms):
    await client.post("/auth/otp/send", json={"phone": PHONE})
    real = sms.sent[PHONE]
    wrong = "000000" if real != "000000" else "111111"

    r1 = await client.post("/auth/otp/verify", json={"phone": PHONE, "code": wrong})
    assert r1.status_code == 400 and "2 attempt" in r1.json()["detail"]
    await client.post("/auth/otp/verify", json={"phone": PHONE, "code": wrong})
    r3 = await client.post("/auth/otp/verify", json={"phone": PHONE, "code": wrong})
    assert r3.status_code == 400
    # OTP is burned now; even the right code fails
    r4 = await client.post("/auth/otp/verify", json={"phone": PHONE, "code": real})
    assert r4.status_code == 400 and "expired" in r4.json()["detail"]


async def test_otp_is_single_use(client, sms):
    await client.post("/auth/otp/send", json={"phone": PHONE})
    code = sms.sent[PHONE]
    assert (
        await client.post("/auth/otp/verify", json={"phone": PHONE, "code": code})
    ).status_code == 200
    assert (
        await client.post("/auth/otp/verify", json={"phone": PHONE, "code": code})
    ).status_code == 400


async def test_resend_cooldown(client, sms):
    assert (await client.post("/auth/otp/send", json={"phone": PHONE})).status_code == 200
    r = await client.post("/auth/otp/send", json={"phone": PHONE})
    assert r.status_code == 429


async def test_refresh_rotates_and_detects_reuse(client, login):
    tokens = await login(PHONE)
    old = tokens["refresh_token"]

    r = await client.post("/auth/refresh", json={"refresh_token": old})
    assert r.status_code == 200
    new = r.json()["refresh_token"]
    assert new != old

    # Replaying the old (rotated) token = theft -> whole family revoked
    r = await client.post("/auth/refresh", json={"refresh_token": old})
    assert r.status_code == 401 and "reuse" in r.json()["detail"]
    r = await client.post("/auth/refresh", json={"refresh_token": new})
    assert r.status_code == 401


async def test_logout_revokes_refresh_token(client, login):
    tokens = await login(PHONE)
    assert (
        await client.post("/auth/logout", json={"refresh_token": tokens["refresh_token"]})
    ).status_code == 204
    r = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 401


async def test_protected_route_needs_token(client):
    assert (await client.get("/profiles/me")).status_code == 401
    r = await client.get("/profiles/me", headers={"Authorization": "Bearer garbage"})
    assert r.status_code == 401


async def test_banned_user_cannot_log_in(client, sms, login):
    tokens = await login(PHONE)
    async with SessionLocal() as db:
        user = await db.scalar(select(User).where(User.phone_hash == hmac_hash(PHONE)))
        user.status = "banned"
        await db.commit()
    # existing access token stops working immediately
    assert (await client.get("/profiles/me", headers=auth(tokens))).status_code == 401
    # refresh is refused
    r = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 401
    # and a fresh OTP login is refused with 403
    async for k in get_redis().scan_iter("otp:cooldown:*"):
        await get_redis().delete(k)
    await client.post("/auth/otp/send", json={"phone": PHONE})
    r = await client.post("/auth/otp/verify", json={"phone": PHONE, "code": sms.sent[PHONE]})
    assert r.status_code == 403
