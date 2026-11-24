import asyncio
import json
import re
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import current_user
from app.core.config import settings
from app.core.redis import get_redis
from app.db.session import SessionLocal, get_db
from app.models import Conversation, Message, Profile, User
from app.models.user import UserStatus
from app.schemas.social import ConversationItem, MessageIn, MessageOut
from app.services.rate_limit import hit
from app.services.realtime import channel, issue_ticket, publish, redeem_ticket
from app.services.social import build_cards, get_viewer, is_blocked

router = APIRouter(tags=["chat"])

# Delivered, but flagged for moderators and shown with a safety warning to the receiver.
_FLAG = [
    re.compile(r"(?:\+?\d[\s\-.]?){10,}"),  # phone numbers
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"),  # emails
    re.compile(r"\b[\w.-]+@(ok\w+|ybl|paytm|upi|apl|ibl|axl|ptyes|pty)\b", re.I),  # UPI ids
    re.compile(r"(https?://|www\.)", re.I),
    re.compile(
        r"\b(send|transfer|need|lend)\b.{0,20}\b(money|rs\.?|rupees|₹|inr|amount)\b"
        r"|\b(gift\s*card|customs|western\s*union|bitcoin|crypto|loan|investment)\b",
        re.I,
    ),
]
_BLOCK = re.compile(r"\b(dowry|dahej)\b", re.I)


def _flagged(body: str) -> bool:
    return any(p.search(body) for p in _FLAG)


def _other(conv: Conversation, me_id: uuid.UUID) -> uuid.UUID:
    return conv.profile_b if conv.profile_a == me_id else conv.profile_a


async def _chat_state(db: AsyncSession, conv: Conversation, me: Profile, other: Profile):
    if conv.status != "open" or await is_blocked(db, me.id, other.id):
        return False, "closed"
    if settings.CHAT_REQUIRES_PREMIUM and not (me.is_premium or other.is_premium):
        return False, "premium_required"
    return True, None


async def _my_conv(db: AsyncSession, conv_id: uuid.UUID, me: Profile) -> Conversation:
    conv = await db.get(Conversation, conv_id)
    if conv is None or me.id not in (conv.profile_a, conv.profile_b):
        raise HTTPException(404, "Conversation not found")
    return conv


def _msg_out(m: Message, sender_public_id: str) -> MessageOut:
    return MessageOut(
        id=m.id,
        conversation_id=str(m.conversation_id),
        sender_public_id=sender_public_id,
        body=m.body,
        flagged=m.flagged,
        created_at=m.created_at,
        read_at=m.read_at,
    )


@router.get("/conversations", response_model=list[ConversationItem])
async def conversations(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    me = await get_viewer(db, user)
    convs = (
        await db.scalars(
            select(Conversation)
            .where(or_(Conversation.profile_a == me.id, Conversation.profile_b == me.id))
            .order_by(func.coalesce(Conversation.last_message_at, Conversation.created_at).desc())
        )
    ).all()
    others = {
        p.id: p
        for p in await db.scalars(
            select(Profile).where(Profile.id.in_([_other(c, me.id) for c in convs]))
        )
    }
    cards = {c["public_id"]: c for c in await build_cards(db, me, list(others.values()))}
    unread = dict(
        (
            await db.execute(
                select(Message.conversation_id, func.count())
                .where(
                    Message.conversation_id.in_([c.id for c in convs]),
                    Message.sender_id != me.id,
                    Message.read_at.is_(None),
                )
                .group_by(Message.conversation_id)
            )
        ).all()
    )
    out = []
    for c in convs:
        o = others.get(_other(c, me.id))
        if o is None:
            continue
        last = await db.scalar(
            select(Message)
            .where(Message.conversation_id == c.id)
            .order_by(Message.id.desc())
            .limit(1)
        )
        ok, reason = await _chat_state(db, c, me, o)
        out.append(
            ConversationItem(
                id=str(c.id),
                profile=cards[o.public_id],
                last_message=last.body if last else None,
                last_message_at=last.created_at if last else None,
                last_from_me=bool(last and last.sender_id == me.id),
                unread=unread.get(c.id, 0),
                can_chat=ok,
                blocked_reason=reason,
            )
        )
    await db.commit()
    return out


@router.get("/conversations/{conv_id}/messages", response_model=list[MessageOut])
async def messages(
    conv_id: uuid.UUID,
    before_id: int | None = None,
    limit: int = Query(50, ge=1, le=100),
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await get_viewer(db, user)
    conv = await _my_conv(db, conv_id, me)
    other = await db.get(Profile, _other(conv, me.id))
    q = select(Message).where(Message.conversation_id == conv.id, Message.deleted_at.is_(None))
    if before_id:
        q = q.where(Message.id < before_id)
    rows = (await db.scalars(q.order_by(Message.id.desc()).limit(limit))).all()
    pub = {me.id: me.public_id, other.id: other.public_id}
    await db.commit()
    return [_msg_out(m, pub[m.sender_id]) for m in reversed(rows)]


@router.post("/conversations/{conv_id}/messages", response_model=MessageOut, status_code=201)
async def send_message(
    conv_id: uuid.UUID,
    body: MessageIn,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await get_viewer(db, user)
    conv = await _my_conv(db, conv_id, me)
    other = await db.get(Profile, _other(conv, me.id))
    ok, reason = await _chat_state(db, conv, me, other)
    if not ok:
        msg = (
            "Chat unlocks when one of you has a Premium plan."
            if reason == "premium_required"
            else "This conversation is closed."
        )
        raise HTTPException(403, msg)
    text = body.body.strip()
    if not text:
        raise HTTPException(422, "Message is empty")
    if _BLOCK.search(text):
        raise HTTPException(422, "Messages about dowry aren't allowed on this platform.")
    if not await hit(get_redis(), f"rl:msg:{me.id}", 20, 60):
        raise HTTPException(429, "You're sending messages too fast. Please slow down.")

    m = Message(conversation_id=conv.id, sender_id=me.id, body=text, flagged=_flagged(text))
    db.add(m)
    conv.last_message_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(m)
    out = _msg_out(m, me.public_id)
    event = {"type": "message", "message": out.model_dump(mode="json")}
    await publish(other.id, event)
    await publish(me.id, event)  # my other tabs
    return out


@router.post("/conversations/{conv_id}/read", status_code=204)
async def mark_read(
    conv_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    conv = await _my_conv(db, conv_id, me)
    res = await db.execute(
        update(Message)
        .where(
            Message.conversation_id == conv.id,
            Message.sender_id != me.id,
            Message.read_at.is_(None),
        )
        .values(read_at=datetime.now(UTC))
    )
    await db.commit()
    if res.rowcount:
        await publish(_other(conv, me.id), {"type": "read", "conversation_id": str(conv.id)})
        await publish(me.id, {"type": "read", "conversation_id": str(conv.id)})


# ---------------- WebSocket ----------------
@router.post("/auth/ws-ticket", tags=["auth"])
async def ws_ticket(user: User = Depends(current_user)):
    return {"ticket": await issue_ticket(user.id)}


@router.websocket("/ws")
async def ws(websocket: WebSocket, ticket: str):
    user_id = await redeem_ticket(ticket)
    if not user_id:
        await websocket.close(code=4401)
        return
    async with SessionLocal() as db:
        user = await db.get(User, uuid.UUID(user_id))
        profile = (
            await db.scalar(select(Profile).where(Profile.user_id == user.id)) if user else None
        )
    if user is None or user.status != UserStatus.ACTIVE or profile is None:
        await websocket.close(code=4403)
        return

    await websocket.accept()
    pubsub = get_redis().pubsub()
    await pubsub.subscribe(channel(profile.id))

    async def pump():
        while True:
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=20)
            if msg is None:
                await websocket.send_text(json.dumps({"type": "ping"}))  # keep-alive
                continue
            await websocket.send_text(msg["data"])

    async def drain():
        while True:
            await websocket.receive_text()  # client pings; also detects disconnects

    tasks = [asyncio.create_task(pump()), asyncio.create_task(drain())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except WebSocketDisconnect:
        pass
    finally:
        for t in tasks:
            t.cancel()
        await pubsub.unsubscribe()
        await pubsub.aclose()
