import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, created_at_col, uuid_pk


class TicketStatus:
    BOT = "bot"  # only the assistant has answered so far
    WAITING = "waiting_team"  # escalated: a person needs to reply
    ANSWERED = "answered"  # team replied; waiting for the member
    CLOSED = "closed"


class SupportTicket(Base):
    """A member's help conversation (assistant + support team). One open at a time."""

    __tablename__ = "support_tickets"
    __table_args__ = (Index("ix_support_tickets_status_updated", "status", "last_message_at"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(20), default=TicketStatus.BOT)
    subject: Mapped[str | None] = mapped_column(String(160))
    topic: Mapped[str | None] = mapped_column(String(40))  # last bot intent
    assigned_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id")
    )
    escalated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SupportMessage(Base):
    __tablename__ = "support_messages"
    __table_args__ = (Index("ix_support_messages_ticket", "ticket_id", "id"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    ticket_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("support_tickets.id", ondelete="CASCADE")
    )
    sender: Mapped[str] = mapped_column(String(10))  # member | bot | staff
    staff_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(10), default="text")  # text | photo | voice
    body: Mapped[str | None] = mapped_column(Text)
    media_key: Mapped[str | None] = mapped_column(String(255))
    duration_s: Mapped[int | None] = mapped_column(Integer)  # voice notes
    meta: Mapped[dict | None] = mapped_column(JSONB)  # bot: intent, suggestions, actions
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()


class ConductViolation(Base):
    """A blocked message/profile text. Stores WHAT rule was broken, never the text itself."""

    __tablename__ = "conduct_violations"
    __table_args__ = (Index("ix_conduct_user_created", "user_id", "created_at"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE")
    )
    context: Mapped[str] = mapped_column(String(20))  # chat | support | profile | interest
    rule: Mapped[str] = mapped_column(String(20))  # vulgar
    created_at: Mapped[datetime] = created_at_col()
