import uuid

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_access_token
from app.db.session import get_db
from app.models import User
from app.models.user import UserRole, UserStatus

bearer = HTTPBearer(auto_error=False)


def client_ip(request: Request) -> str | None:
    # Run uvicorn with --proxy-headers --forwarded-allow-ips=<caddy ip> in prod so this is
    # the real client IP, not the reverse proxy's.
    return request.client.host if request.client else None


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    unauthorized = HTTPException(
        status.HTTP_401_UNAUTHORIZED, "Not authenticated", {"WWW-Authenticate": "Bearer"}
    )
    if creds is None:
        raise unauthorized
    try:
        payload = decode_access_token(creds.credentials)
        user_id = uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError):
        raise unauthorized from None
    user = await db.get(User, user_id)
    if user is None or user.status != UserStatus.ACTIVE:
        raise unauthorized
    return user


async def current_staff(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Staff endpoints accept ONLY tokens from the staff login (password + TOTP),
    never a member's OTP token — even if that account somehow had a staff role."""
    denied = HTTPException(status.HTTP_401_UNAUTHORIZED, "Staff login required")
    if creds is None:
        raise denied
    try:
        payload = decode_access_token(creds.credentials)
        user_id = uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError):
        raise denied from None
    if payload.get("scope") != "admin":
        raise denied
    user = await db.get(User, user_id)
    if (
        user is None
        or user.status != UserStatus.ACTIVE
        or user.role
        not in (
            UserRole.MODERATOR,
            UserRole.ADMIN,
        )
    ):
        raise denied
    return user


async def current_admin(user: User = Depends(current_staff)) -> User:
    if user.role != UserRole.ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admins can do this")
    return user
