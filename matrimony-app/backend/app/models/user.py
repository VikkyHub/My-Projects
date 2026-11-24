import uuid
from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, LargeBinary, String
from sqlalchemy.dialects.postgresql import INET, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, created_at_col, uuid_pk


class UserRole:
    MEMBER = "member"
    MODERATOR = "moderator"
    ADMIN = "admin"


class UserStatus:
    ACTIVE = "active"
    SUSPENDED = "suspended"
    BANNED = "banned"
    DELETED = "deleted"


class User(Base):
    """The login account. May belong to the candidate OR a parent/sibling managing the profile."""

    __tablename__ = "users"
    id: Mapped[uuid.UUID] = uuid_pk()
    # Phone: HMAC for lookup/uniqueness + AES-GCM ciphertext for display. Never plaintext.
    phone_hash: Mapped[str] = mapped_column(String(64), unique=True)
    phone_enc: Mapped[bytes] = mapped_column(LargeBinary)
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    email_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    email_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    role: Mapped[str] = mapped_column(String(20), default=UserRole.MEMBER)
    status: Mapped[str] = mapped_column(String(20), default=UserStatus.ACTIVE)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    # All tokens from one login share a family; reuse of a rotated token revokes the family.
    family_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    device_id: Mapped[str | None] = mapped_column(String(100))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # rotated | logout | reuse. Only "rotated" tokens get the multi-tab grace window.
    revoked_reason: Mapped[str | None] = mapped_column(String(20))
    created_at: Mapped[datetime] = created_at_col()


class Consent(Base):
    """DPDP: an append-only record of what the user agreed to, which version, and when."""

    __tablename__ = "consents"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # terms | privacy | marketing | id_verification | candidate_consent
    purpose: Mapped[str] = mapped_column(String(40))
    version: Mapped[str] = mapped_column(String(40))
    granted: Mapped[bool] = mapped_column(Boolean)
    ip: Mapped[str | None] = mapped_column(INET)
    created_at: Mapped[datetime] = created_at_col()


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    fcm_token: Mapped[str | None] = mapped_column(String(255))
    platform: Mapped[str | None] = mapped_column(String(20))  # web | android | ios
    fingerprint: Mapped[str | None] = mapped_column(String(128), index=True)  # multi-account check
    ip: Mapped[str | None] = mapped_column(INET)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AdminAction(Base):
    __tablename__ = "admin_actions"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    admin_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    target_type: Mapped[str] = mapped_column(String(30))
    target_id: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(40))
    reason: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = created_at_col()
