"""Application log: record_event() writes one row to app_events.

- Uses its OWN database session, so an event is kept even if the request's
  transaction rolls back, and a logging failure never breaks the request.
- Also mirrored to the console (structlog) for server-side log shipping.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Literal

import structlog
from fastapi import Request
from sqlalchemy import delete

from app.core.config import settings
from app.db.session import SessionLocal
from app.models import AppEvent

log = structlog.get_logger("app")

Level = Literal["info", "warning", "error"]
Category = Literal[
    "auth", "staff", "profile", "photo", "interest", "chat", "safety", "support", "system"
]


def _ip(request: Request | None) -> str | None:
    return request.client.host if request and request.client else None


async def record_event(
    event: str,
    *,
    category: Category,
    level: Level = "info",
    message: str | None = None,
    actor: str | None = None,
    actor_type: Literal["member", "staff", "anonymous"] | None = None,
    request: Request | None = None,
    meta: dict | None = None,
) -> None:
    ua = request.headers.get("user-agent", "")[:200] if request else None
    rid = getattr(request.state, "request_id", None) if request else None
    getattr(log, "error" if level == "error" else "warning" if level == "warning" else "info")(
        event, category=category, actor=actor, request_id=rid
    )
    try:
        async with SessionLocal() as s:
            s.add(
                AppEvent(
                    level=level,
                    category=category,
                    event=event,
                    actor=actor,
                    actor_type=actor_type,
                    message=message,
                    ip=_ip(request),
                    user_agent=ua,
                    request_id=rid,
                    meta=meta,
                )
            )
            await s.commit()
    except Exception as e:  # never let logging break the app
        # NB: structlog reserves the keyword "event" for the message itself
        log.error("app_event_write_failed", error=str(e)[:200], event_name=event)


async def purge_old_events() -> int:
    cutoff = datetime.now(UTC) - timedelta(days=settings.APP_LOG_RETENTION_DAYS)
    async with SessionLocal() as s:
        res = await s.execute(delete(AppEvent).where(AppEvent.created_at < cutoff))
        await s.commit()
        return res.rowcount or 0


async def purge_loop() -> None:
    """Background task: enforce log retention every 6 hours."""
    while True:
        try:
            n = await purge_old_events()
            if n:
                log.info("app_events_purged", rows=n)
        except Exception as e:
            log.error("app_events_purge_failed", error=str(e)[:200])
        await asyncio.sleep(6 * 3600)
