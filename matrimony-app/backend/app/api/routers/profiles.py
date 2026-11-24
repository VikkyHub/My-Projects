from fastapi import APIRouter, Depends, HTTPException, Request, status
from redis.asyncio import Redis
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import client_ip, current_user
from app.core.redis import get_redis
from app.core.security import decrypt
from app.db.session import get_db
from app.models import Profile, User
from app.schemas.auth import OtpSendOut
from app.schemas.profile import (
    CandidateConsentVerifyIn,
    MyProfileOut,
    ProfileCreate,
    ProfileUpdate,
)
from app.services import otp
from app.services import profiles as svc
from app.services.sms import SmsProvider, get_sms_provider

router = APIRouter(prefix="/profiles", tags=["profiles"])

CONSENT = "candidate_consent"


def _raise(e: svc.ProfileError | otp.OtpError):
    raise HTTPException(e.status_code, e.message) from None


async def _my_profile(user: User, db: AsyncSession) -> Profile:
    p = await svc.get_my_profile(db, user)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Create your profile first")
    return p


@router.post("", response_model=MyProfileOut, status_code=status.HTTP_201_CREATED)
async def create_profile(
    body: ProfileCreate,
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create the profile for this account. If created_by != 'self', the profile stays
    in 'draft' (invisible) until the candidate confirms with an OTP on their own phone."""
    try:
        p = await svc.create_profile(db, user, body, client_ip(request))
    except svc.ProfileError as e:
        _raise(e)
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Profile already exists") from None
    return svc.to_my_profile_out(p)


@router.get("/me", response_model=MyProfileOut)
async def get_me(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    return svc.to_my_profile_out(await _my_profile(user, db))


@router.patch("/me", response_model=MyProfileOut)
async def update_me(
    body: ProfileUpdate,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    p = await _my_profile(user, db)
    try:
        p = await svc.update_profile(db, p, body)
    except svc.ProfileError as e:
        await db.rollback()
        _raise(e)
    return svc.to_my_profile_out(p)


@router.post("/me/candidate-consent/send", response_model=OtpSendOut)
async def send_candidate_consent(
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    sms: SmsProvider = Depends(get_sms_provider),
):
    """Sends an OTP to the CANDIDATE's phone (not the account holder's)."""
    p = await _my_profile(user, db)
    if p.candidate_consent_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Candidate has already consented")
    try:
        sent = await otp.send_otp(
            redis, sms, decrypt(p.candidate_phone_enc), CONSENT, client_ip(request)
        )
    except otp.OtpError as e:
        _raise(e)
    return OtpSendOut(expires_in=sent.expires_in, resend_after=sent.resend_after)


@router.post("/me/candidate-consent/verify", response_model=MyProfileOut)
async def verify_candidate_consent(
    body: CandidateConsentVerifyIn,
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
):
    p = await _my_profile(user, db)
    if p.candidate_consent_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Candidate has already consented")
    try:
        await otp.verify_otp(redis, decrypt(p.candidate_phone_enc), CONSENT, body.code)
    except otp.OtpError as e:
        _raise(e)
    await svc.confirm_candidate_consent(db, p, client_ip(request))
    await db.refresh(p)
    return svc.to_my_profile_out(p)
