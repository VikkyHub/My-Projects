from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Request, status
from redis.asyncio import Redis
from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import client_ip
from app.core.redis import get_redis
from app.core.security import encrypt, hmac_hash
from app.db.session import get_db
from app.models import Profile, User
from app.models.user import UserStatus
from app.schemas.auth import LoginOut, OtpSendOut, OtpVerifyIn, PhoneIn, RefreshIn, TokenOut
from app.services import otp, tokens
from app.services.sms import SmsProvider, get_sms_provider

router = APIRouter(prefix="/auth", tags=["auth"])

LOGIN = "login"


@router.post("/otp/send", response_model=OtpSendOut)
async def send_login_otp(
    body: PhoneIn,
    request: Request,
    redis: Redis = Depends(get_redis),
    sms: SmsProvider = Depends(get_sms_provider),
):
    """Step 1 of login/registration. Same response whether or not the number is registered
    (prevents checking which numbers have accounts)."""
    try:
        sent = await otp.send_otp(redis, sms, body.phone, LOGIN, client_ip(request))
    except otp.OtpError as e:
        raise HTTPException(e.status_code, e.message) from None
    return OtpSendOut(expires_in=sent.expires_in, resend_after=sent.resend_after)


@router.post("/otp/verify", response_model=LoginOut)
async def verify_login_otp(
    body: OtpVerifyIn,
    redis: Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
):
    """Step 2. Creates the account on first successful verification."""
    try:
        await otp.verify_otp(redis, body.phone, LOGIN, body.code)
    except otp.OtpError as e:
        raise HTTPException(e.status_code, e.message) from None

    now = datetime.now(UTC)
    ph = hmac_hash(body.phone)
    user = await db.scalar(select(User).where(User.phone_hash == ph))
    is_new = user is None
    if is_new:
        user = User(phone_hash=ph, phone_enc=encrypt(body.phone), phone_verified_at=now)
        db.add(user)
        await db.flush()
    elif user.status != UserStatus.ACTIVE:
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Account is {user.status}")

    user.last_login_at = now
    pair = await tokens.issue_tokens(db, user, body.device_id)
    has_profile = (
        False
        if is_new
        else bool(await db.scalar(select(exists().where(Profile.user_id == user.id))))
    )
    await db.commit()
    return LoginOut(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
        is_new_user=is_new,
        has_profile=has_profile,
    )


@router.post("/refresh", response_model=TokenOut)
async def refresh(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    try:
        pair = await tokens.rotate(db, body.refresh_token)
    except tokens.TokenError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(e)) from None
    return TokenOut(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    await tokens.revoke(db, body.refresh_token)
