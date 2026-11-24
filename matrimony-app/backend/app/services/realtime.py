"""Real-time fan-out: publish events to a member's Redis channel; every API worker holding
that member's WebSocket forwards them. Works with any number of workers/servers."""

import json
import secrets
import uuid

from app.core.redis import get_redis

TICKET_TTL = 60


def channel(profile_id: uuid.UUID | str) -> str:
    return f"user:{profile_id}"


async def publish(profile_id: uuid.UUID | str, event: dict) -> None:
    await get_redis().publish(channel(profile_id), json.dumps(event, default=str))


async def issue_ticket(user_id: uuid.UUID) -> str:
    """Short-lived one-time ticket so the long-lived JWT never goes in a WebSocket URL."""
    t = secrets.token_urlsafe(24)
    await get_redis().set(f"wsticket:{t}", str(user_id), ex=TICKET_TTL)
    return t


async def redeem_ticket(ticket: str) -> str | None:
    r = get_redis()
    key = f"wsticket:{ticket}"
    pipe = r.pipeline()
    pipe.get(key)
    pipe.delete(key)
    user_id, _ = await pipe.execute()
    return user_id
