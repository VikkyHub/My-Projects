import uuid

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_access_token
from app.db.session import get_db
from app.models import User
from app.models.user import UserStatus

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
