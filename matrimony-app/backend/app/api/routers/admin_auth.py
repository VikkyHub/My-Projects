"""Staff login: email + password, then a TOTP code from an authenticator app.

Separate from member login on purpose: members use phone OTP; staff accounts can see many
people's data, so they need two independent secrets, lock out after repeated failures,
and get short sessions (see tokens.issue_tokens).
"""

import json
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import client_ip, current_staff
from app.core.config import settings
from app.core.redis import get_redis
from app.core.security import (
    decrypt,
    encrypt,
    hash_password,
    hmac_hash,
    new_totp_secret,
    totp_uri,
    verify_password,
    verify_totp,
)
from app.db.session import get_db
from app.models import AdminAction, User
from app.models.user import UserRole, UserStatus
from app.schemas.admin import StaffLoginIn, StaffLoginOut, StaffMe, StaffTokens, StaffVerifyIn
from app.services import tokens
from app.services.rate_limit import hit

router = APIRouter(prefix="/admin/auth", tags=["admin auth"])
TICKET_TTL = 300
MAX_CODE_TRIES = 5
BAD = HTTPException(401, "Invalid email or password")


def staff_me(u: User) -> StaffMe:
    return StaffMe(
        id=str(u.id), name=u.name, email=decrypt(u.email_enc) if u.email_enc else None, role=u.role
    )


@router.post("/login", response_model=StaffLoginOut)
async def login(body: StaffLoginIn, request: Request, db: AsyncSession = Depends(get_db)):
    ip = client_ip(request) or "?"
    if not await hit(get_redis(), f"rl:adminlogin:{ip}", 20, 900):
        raise HTTPException(429, "Too many attempts from this network. Try again later.")

    email = body.email.strip().lower()
    u = await db.scalar(select(User).where(User.email_hash == hmac_hash(email)))
    staff = u is not None and u.role in (UserRole.MODERATOR, UserRole.ADMIN)
    now = datetime.now(UTC)
    if staff and u.locked_until and u.locked_until > now:
        mins = int((u.locked_until - now).total_seconds() // 60) + 1
        raise HTTPException(429, f"Account locked after failed attempts. Try again in {mins} min.")

    if not verify_password(body.password, u.password_hash if staff else None):
        if staff:
            u.failed_logins = (u.failed_logins or 0) + 1
            if u.failed_logins >= settings.ADMIN_MAX_FAILED_LOGINS:
                u.locked_until = now + timedelta(minutes=settings.ADMIN_LOCKOUT_MINUTES)
                u.failed_logins = 0
                db.add(
                    AdminAction(
                        admin_id=u.id,
                        target_type="staff",
                        target_id=str(u.id),
                        action="locked_out",
                        reason=f"ip {ip}",
                    )
                )
            await db.commit()
        raise BAD
    if u.status != UserStatus.ACTIVE:
        raise HTTPException(403, "This staff account is disabled")

    u.failed_logins = 0
    enroll = u.totp_enabled_at is None
    secret = None
    if enroll:
        secret = new_totp_secret()
        u.totp_secret_enc = encrypt(secret)
    await db.commit()

    ticket = secrets.token_urlsafe(24)
    await get_redis().set(
        f"adminmfa:{ticket}", json.dumps({"uid": str(u.id), "tries": 0}), ex=TICKET_TTL
    )
    return StaffLoginOut(
        step="enroll" if enroll else "totp",
        ticket=ticket,
        must_change_password=u.must_change_password,
        otpauth_uri=totp_uri(secret, email, settings.APP_NAME + " Admin") if enroll else None,
        secret=secret,
    )


@router.post("/verify", response_model=StaffTokens)
async def verify(body: StaffVerifyIn, request: Request, db: AsyncSession = Depends(get_db)):
    r = get_redis()
    key = f"adminmfa:{body.ticket}"
    raw = await r.get(key)
    if not raw:
        raise HTTPException(401, "Login expired. Please start again.")
    data = json.loads(raw)
    u = await db.get(User, uuid.UUID(data["uid"]))
    if u is None or u.status != UserStatus.ACTIVE or not u.totp_secret_enc:
        raise HTTPException(401, "Login expired. Please start again.")

    if not verify_totp(decrypt(u.totp_secret_enc), body.code):
        data["tries"] += 1
        if data["tries"] >= MAX_CODE_TRIES:
            await r.delete(key)
            raise HTTPException(401, "Too many wrong codes. Please start again.")
        await r.set(key, json.dumps(data), keepttl=True)
        raise HTTPException(401, "That code isn't right. Check your authenticator app.")

    if u.must_change_password:
        if not body.new_password:
            raise HTTPException(422, "Please set a new password to continue")
        if verify_password(body.new_password, u.password_hash):
            raise HTTPException(422, "Choose a password different from the temporary one")
        u.password_hash = hash_password(body.new_password)
        u.must_change_password = False

    await r.delete(key)
    first = u.totp_enabled_at is None
    if first:
        u.totp_enabled_at = datetime.now(UTC)
    u.last_login_at = datetime.now(UTC)
    db.add(
        AdminAction(
            admin_id=u.id,
            target_type="staff",
            target_id=str(u.id),
            action="login_2fa_setup" if first else "login",
            reason=f"ip {client_ip(request)}",
        )
    )
    pair = await tokens.issue_tokens(db, u, device_id="admin-web", scope="admin")
    await db.commit()
    return StaffTokens(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
        staff=staff_me(u),
    )


@router.get("/me", response_model=StaffMe)
async def me(u: User = Depends(current_staff)):
    return staff_me(u)
