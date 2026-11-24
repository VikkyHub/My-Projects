import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    SmallInteger,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, created_at_col, uuid_pk


def _profile_fk(**kw):
    return mapped_column(UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), **kw)


class Interest(Base):
    __tablename__ = "interests"
    __table_args__ = (
        CheckConstraint("sender_id <> receiver_id", name="not_self"),
        # Only one live interest per pair, regardless of direction.
        Index(
            "ux_interest_pair",
            func.least(text("sender_id"), text("receiver_id")),
            func.greatest(text("sender_id"), text("receiver_id")),
            unique=True,
            postgresql_where=text("status IN ('pending', 'accepted')"),
        ),
        Index("ix_interest_receiver", "receiver_id", "status", "created_at"),
    )
    id: Mapped[uuid.UUID] = uuid_pk()
    sender_id: Mapped[uuid.UUID] = _profile_fk()
    receiver_id: Mapped[uuid.UUID] = _profile_fk()
    status: Mapped[str] = mapped_column(String(20), default="pending")
    note: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = created_at_col()
    responded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Conversation(Base):
    """Created ONLY when an interest is accepted."""

    __tablename__ = "conversations"
    id: Mapped[uuid.UUID] = uuid_pk()
    interest_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("interests.id"), unique=True
    )
    profile_a: Mapped[uuid.UUID] = _profile_fk(index=True)
    profile_b: Mapped[uuid.UUID] = _profile_fk(index=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (
        CheckConstraint("length(body) <= 2000", name="body_len"),
        Index("ix_messages_conv_id", "conversation_id", "id"),
    )
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("conversations.id", ondelete="CASCADE")
    )
    sender_id: Mapped[uuid.UUID] = _profile_fk()
    body: Mapped[str] = mapped_column(Text)
    flagged: Mapped[bool] = mapped_column(Boolean, default=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Block(Base):
    __tablename__ = "blocks"
    __table_args__ = (PrimaryKeyConstraint("blocker_id", "blocked_id"),)
    blocker_id: Mapped[uuid.UUID] = _profile_fk()
    blocked_id: Mapped[uuid.UUID] = _profile_fk(index=True)
    created_at: Mapped[datetime] = created_at_col()


class Shortlist(Base):
    __tablename__ = "shortlists"
    __table_args__ = (PrimaryKeyConstraint("owner_id", "target_id"),)
    owner_id: Mapped[uuid.UUID] = _profile_fk()
    target_id: Mapped[uuid.UUID] = _profile_fk()
    created_at: Mapped[datetime] = created_at_col()


class ProfileView(Base):
    __tablename__ = "profile_views"
    __table_args__ = (Index("ix_profile_views_viewed", "viewed_id", "created_at"),)
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    viewer_id: Mapped[uuid.UUID] = _profile_fk()
    viewed_id: Mapped[uuid.UUID] = _profile_fk()
    created_at: Mapped[datetime] = created_at_col()


class Report(Base):
    __tablename__ = "reports"
    id: Mapped[uuid.UUID] = uuid_pk()
    reporter_id: Mapped[uuid.UUID] = _profile_fk()
    reported_id: Mapped[uuid.UUID] = _profile_fk(index=True)
    # fake | harassment | married | scam_money | dowry | obscene | underage | other
    reason: Mapped[str] = mapped_column(String(30))
    details: Mapped[str | None] = mapped_column(Text)
    message_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("messages.id"))
    status: Mapped[str] = mapped_column(String(20), default="open", index=True)
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id")
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()


class DailyMatch(Base):
    __tablename__ = "daily_matches"
    __table_args__ = (PrimaryKeyConstraint("profile_id", "for_date", "match_id"),)
    profile_id: Mapped[uuid.UUID] = _profile_fk()
    match_id: Mapped[uuid.UUID] = _profile_fk()
    for_date: Mapped[date] = mapped_column(Date)
    score: Mapped[int] = mapped_column(SmallInteger)
