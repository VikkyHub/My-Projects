import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import current_user
from app.core.config import settings
from app.db.session import get_db
from app.models import Conversation, Interest, Message, Profile, User
from app.schemas.social import InterestCounts, InterestCreate, InterestItem
from app.services.events import record_event
from app.services.realtime import publish
from app.services.social import (
    blocked_clause,
    build_cards,
    get_target,
    get_viewer,
    ist_day_start_utc,
    require_active,
)

router = APIRouter(prefix="/interests", tags=["interests"])
DECLINE_COOLDOWN = timedelta(days=30)


def _limit(me: Profile) -> int:
    return settings.PREMIUM_DAILY_INTERESTS if me.is_premium else settings.FREE_DAILY_INTERESTS


async def _sent_today(db: AsyncSession, me: Profile) -> int:
    return (
        await db.scalar(
            select(func.count())
            .select_from(Interest)
            .where(Interest.sender_id == me.id, Interest.created_at >= ist_day_start_utc())
        )
    ) or 0


@router.post("", response_model=InterestItem, status_code=201)
async def send_interest(
    body: InterestCreate,
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await get_viewer(db, user)
    require_active(me, "send interests")
    t = await get_target(db, me, body.public_id)
    if t.id == me.id:
        raise HTTPException(422, "You can't send interest to yourself")
    if t.gender == me.gender:
        raise HTTPException(422, "Interests can only be sent to the opposite gender")

    pair = or_(
        and_(Interest.sender_id == me.id, Interest.receiver_id == t.id),
        and_(Interest.sender_id == t.id, Interest.receiver_id == me.id),
    )
    live = await db.scalar(
        select(Interest).where(pair, Interest.status.in_(("pending", "accepted")))
    )
    if live:
        if live.status == "accepted":
            raise HTTPException(409, "You're already connected")
        if live.sender_id == t.id:
            raise HTTPException(409, f"{t.first_name} already sent you an interest — accept it!")
        raise HTTPException(409, "Interest already sent")
    declined = await db.scalar(
        select(Interest.id).where(
            Interest.sender_id == me.id,
            Interest.receiver_id == t.id,
            Interest.status == "declined",
            Interest.responded_at >= datetime.now(UTC) - DECLINE_COOLDOWN,
        )
    )
    if declined:
        raise HTTPException(
            409, f"{t.first_name} declined recently. You can't send another for now."
        )

    used = await _sent_today(db, me)
    if used >= _limit(me):
        hint = "" if me.is_premium else " Premium members can send up to 50 a day."
        await record_event(
            "interest_limit_reached",
            category="interest",
            actor=me.public_id,
            actor_type="member",
            message=f"Daily limit of {_limit(me)} reached",
            request=request,
        )
        raise HTTPException(429, f"You've used today's {_limit(me)} interests.{hint}")

    i = Interest(sender_id=me.id, receiver_id=t.id, note=body.note)
    db.add(i)
    await db.commit()
    await db.refresh(i)
    await publish(t.id, {"type": "interest", "from": me.first_name})
    await record_event(
        "interest_sent",
        category="interest",
        actor=me.public_id,
        actor_type="member",
        message=f"Interest sent to {t.public_id}",
        request=request,
    )
    card = (await build_cards(db, me, [t]))[0]
    return InterestItem(
        id=str(i.id),
        status=i.status,
        direction="sent",
        note=i.note,
        created_at=i.created_at,
        responded_at=None,
        profile=card,
    )


@router.get("", response_model=list[InterestItem])
async def list_interests(
    box: Literal["received", "sent", "accepted"] = "received",
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await get_viewer(db, user)
    if box == "received":
        cond = and_(Interest.receiver_id == me.id, Interest.status == "pending")
    elif box == "sent":
        cond = and_(Interest.sender_id == me.id, Interest.status.in_(("pending", "declined")))
    else:
        cond = and_(
            or_(Interest.sender_id == me.id, Interest.receiver_id == me.id),
            Interest.status == "accepted",
        )
    rows = (
        await db.scalars(
            select(Interest).where(cond).order_by(Interest.created_at.desc()).limit(200)
        )
    ).all()
    other_ids = [(i.receiver_id if i.sender_id == me.id else i.sender_id) for i in rows]
    profiles = {
        p.id: p
        for p in (
            await db.scalars(
                select(Profile).where(Profile.id.in_(other_ids), blocked_clause(me.id, Profile.id))
            )
        )
    }
    cards = {c["public_id"]: c for c in await build_cards(db, me, list(profiles.values()))}
    await db.commit()
    out = []
    for i, oid in zip(rows, other_ids, strict=True):
        p = profiles.get(oid)
        if p is None:
            continue
        out.append(
            InterestItem(
                id=str(i.id),
                status=i.status,
                direction="sent" if i.sender_id == me.id else "received",
                note=i.note,
                created_at=i.created_at,
                responded_at=i.responded_at,
                profile=cards[p.public_id],
            )
        )
    return out


async def _get_own(db: AsyncSession, interest_id: uuid.UUID, me: Profile, role: str) -> Interest:
    i = await db.get(Interest, interest_id, with_for_update=True)
    owner = i.receiver_id if i and role == "receiver" else (i.sender_id if i else None)
    if i is None or owner != me.id:
        raise HTTPException(404, "Interest not found")
    if i.status != "pending":
        raise HTTPException(409, f"This interest is already {i.status}")
    return i


@router.post("/{interest_id}/accept", response_model=dict)
async def accept(
    interest_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    require_active(me, "accept interests")
    i = await _get_own(db, interest_id, me, "receiver")
    i.status = "accepted"
    i.responded_at = datetime.now(UTC)
    conv = Conversation(interest_id=i.id, profile_a=i.sender_id, profile_b=i.receiver_id)
    db.add(conv)
    await db.commit()
    await publish(i.sender_id, {"type": "interest_accepted", "by": me.first_name})
    await record_event(
        "interest_accepted",
        category="interest",
        actor=me.public_id,
        actor_type="member",
        message="Interest accepted — conversation opened",
    )
    return {"status": "accepted", "conversation_id": str(conv.id)}


@router.post("/{interest_id}/decline", response_model=dict)
async def decline(
    interest_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    i = await _get_own(db, interest_id, me, "receiver")
    i.status = "declined"
    i.responded_at = datetime.now(UTC)
    await db.commit()
    await publish(i.sender_id, {"type": "refresh"})
    return {"status": "declined"}


@router.post("/{interest_id}/withdraw", response_model=dict)
async def withdraw(
    interest_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    i = await _get_own(db, interest_id, me, "sender")
    i.status = "withdrawn"
    i.responded_at = datetime.now(UTC)
    await db.commit()
    await publish(i.receiver_id, {"type": "refresh"})
    return {"status": "withdrawn"}


@router.get("/counts", response_model=InterestCounts)
async def counts(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    me = await get_viewer(db, user)
    received = await db.scalar(
        select(func.count())
        .select_from(Interest)
        .join(Profile, Profile.id == Interest.sender_id)
        .where(
            Interest.receiver_id == me.id,
            Interest.status == "pending",
            blocked_clause(me.id, Profile.id),
        )
    )
    unread = await db.scalar(
        select(func.count())
        .select_from(Message)
        .join(Conversation, Conversation.id == Message.conversation_id)
        .where(
            or_(Conversation.profile_a == me.id, Conversation.profile_b == me.id),
            Conversation.status == "open",
            Message.sender_id != me.id,
            Message.read_at.is_(None),
        )
    )
    sent = await _sent_today(db, me)
    await db.commit()
    return InterestCounts(
        received_pending=received or 0,
        unread_messages=unread or 0,
        sent_today=sent,
        daily_limit=_limit(me),
    )
