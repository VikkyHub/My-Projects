"""Refresh-token rotation with reuse detection.

Every refresh revokes the presented token and issues a new one in the same family.
If an already-revoked token is presented again, someone copied it -> revoke the whole
family (logs out the attacker and the real user, who simply logs in again).
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import create_access_token, new_refresh_token, sha256
from app.models import RefreshToken, User
from app.models.user import UserStatus


class TokenError(Exception):
    pass


@dataclass
class TokenPair:
    access_token: str
    refresh_token: str
    expires_in: int


async def issue_tokens(
    db: AsyncSession, user: User, device_id: str | None, family_id: uuid.UUID | None = None
) -> TokenPair:
    raw = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=sha256(raw),
            family_id=family_id or uuid.uuid4(),
            device_id=device_id,
            expires_at=datetime.now(UTC) + timedelta(days=settings.REFRESH_TOKEN_DAYS),
        )
    )
    access, expires_in = create_access_token(user.id, user.role)
    return TokenPair(access, raw, expires_in)


async def rotate(db: AsyncSession, raw_refresh: str) -> TokenPair:
    now = datetime.now(UTC)
    rt = await db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == sha256(raw_refresh)).with_for_update()
    )
    if rt is None:
        raise TokenError("Invalid refresh token")

    if rt.revoked_at is not None:
        # Reuse of a rotated token => theft. Kill the family.
        await db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == rt.family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await db.commit()
        raise TokenError("Refresh token reuse detected. Please log in again.")

    if rt.expires_at <= now:
        raise TokenError("Refresh token expired")

    user = await db.get(User, rt.user_id)
    if user is None or user.status != UserStatus.ACTIVE:
        raise TokenError("Account is not active")

    rt.revoked_at = now
    pair = await issue_tokens(db, user, rt.device_id, family_id=rt.family_id)
    await db.commit()
    return pair


async def revoke(db: AsyncSession, raw_refresh: str) -> None:
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == sha256(raw_refresh), RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    await db.commit()
