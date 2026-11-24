"""Refresh-token rotation with reuse detection.

Every refresh revokes the presented token and issues a new one in the same family.
If an already-revoked token is presented again after a short grace period (which covers
several browser tabs refreshing at once), someone copied it -> revoke the whole family
(logs out the attacker and the real user, who simply logs in again).
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, update
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
    db: AsyncSession,
    user: User,
    device_id: str | None,
    family_id: uuid.UUID | None = None,
    scope: str = "member",
    session_expires_at: datetime | None = None,
) -> TokenPair:
    """Member sessions last 30 days. Staff ("admin" scope) sessions end after
    ADMIN_IDLE_MINUTES without activity, and always at session_expires_at (8h after login)."""
    now = datetime.now(UTC)
    if scope == "admin":
        session_expires_at = session_expires_at or now + timedelta(
            hours=settings.ADMIN_SESSION_HOURS
        )
        expires_at = min(now + timedelta(minutes=settings.ADMIN_IDLE_MINUTES), session_expires_at)
    else:
        expires_at = now + timedelta(days=settings.REFRESH_TOKEN_DAYS)
    raw = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=sha256(raw),
            family_id=family_id or uuid.uuid4(),
            device_id=device_id,
            expires_at=expires_at,
            scope=scope,
            session_expires_at=session_expires_at,
        )
    )
    access, expires_in = create_access_token(user.id, user.role, scope)
    return TokenPair(access, raw, expires_in)


async def rotate(db: AsyncSession, raw_refresh: str) -> TokenPair:
    now = datetime.now(UTC)
    rt = await db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == sha256(raw_refresh)).with_for_update()
    )
    if rt is None:
        raise TokenError("Invalid refresh token")

    if rt.revoked_at is not None:
        in_grace = (now - rt.revoked_at).total_seconds() <= settings.REFRESH_REUSE_GRACE_SECONDS
        if rt.revoked_reason == "rotated" and in_grace:
            # Another tab/request refreshed with the same token moments ago: not theft.
            user = await db.get(User, rt.user_id)
            if user is None or user.status != UserStatus.ACTIVE:
                raise TokenError("Account is not active")
            pair = await issue_tokens(
                db, user, rt.device_id, rt.family_id, rt.scope, rt.session_expires_at
            )
            await db.commit()
            return pair
        # Reuse of a rotated token long after => theft. Kill the family.
        if rt.revoked_reason == "rotated":
            # Kill every token in the family, including recently rotated ones still in grace
            await db.execute(
                update(RefreshToken)
                .where(RefreshToken.family_id == rt.family_id, RefreshToken.revoked_at.is_(None))
                .values(revoked_at=now)
            )
            await db.execute(
                update(RefreshToken)
                .where(RefreshToken.family_id == rt.family_id)
                .values(revoked_reason="reuse")
            )
            await db.commit()
            raise TokenError("Refresh token reuse detected. Please log in again.")
        raise TokenError("Session ended. Please log in again.")

    if rt.expires_at <= now:
        raise TokenError("Refresh token expired")

    user = await db.get(User, rt.user_id)
    if user is None or user.status != UserStatus.ACTIVE:
        raise TokenError("Account is not active")

    rt.revoked_at = now
    rt.revoked_reason = "rotated"
    pair = await issue_tokens(db, user, rt.device_id, rt.family_id, rt.scope, rt.session_expires_at)
    await db.commit()
    return pair


async def revoke(db: AsyncSession, raw_refresh: str) -> None:
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == sha256(raw_refresh))
        .values(
            revoked_at=func.coalesce(RefreshToken.revoked_at, datetime.now(UTC)),
            revoked_reason="logout",
        )
    )
    await db.commit()
