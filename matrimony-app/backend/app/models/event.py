from datetime import datetime

from sqlalchemy import BigInteger, Index, String, Text
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, created_at_col


class AppEvent(Base):
    """Application log shown in the admin panel (sign-ins, security, activity, errors).

    Privacy: never store full phone numbers, OTPs, passwords or chat text here.
    Rows are deleted after APP_LOG_RETENTION_DAYS (DPDP storage limitation).
    """

    __tablename__ = "app_events"
    __table_args__ = (
        Index("ix_app_events_created", "created_at"),
        Index("ix_app_events_cat_created", "category", "created_at"),
        Index("ix_app_events_level_created", "level", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    created_at: Mapped[datetime] = created_at_col()
    level: Mapped[str] = mapped_column(String(10))  # info | warning | error
    # auth | staff | profile | photo | interest | chat | safety | system
    category: Mapped[str] = mapped_column(String(20))
    event: Mapped[str] = mapped_column(String(50))
    actor_type: Mapped[str | None] = mapped_column(String(10))  # member | staff | anonymous
    actor: Mapped[str | None] = mapped_column(String(120))  # public_id, staff email, masked phone
    message: Mapped[str | None] = mapped_column(Text)
    ip: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(200))
    request_id: Mapped[str | None] = mapped_column(String(32))
    meta: Mapped[dict | None] = mapped_column(JSONB)
