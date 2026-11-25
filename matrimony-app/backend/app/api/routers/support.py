"""Help chat: the assistant answers first; the support team takes over when needed.

Member endpoints (/support/...) work even before a profile exists (login problems,
registration questions). Staff endpoints live under /admin/support.
"""

import re
import uuid
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import current_staff, current_user
from app.core.config import settings
from app.core.redis import get_redis
from app.core.security import decrypt, mask_phone
from app.db.session import get_db
from app.models import Profile, SupportMessage, SupportTicket, User
from app.models.support import TicketStatus
from app.services import images
from app.services.conduct import VULGAR_MESSAGE, check_text, record_violation
from app.services.events import record_event
from app.services.helpbot import BY_KEY, WELCOME, answer, chips
from app.services.rate_limit import hit
from app.services.realtime import publish_account
from app.services.storage import get_storage

router = APIRouter(tags=["support"])
_URGENT_WORDS = "threat|blackmail|suicide|kill|harass|stalk|extort|police"
URGENT = re.compile(rf"\b({_URGENT_WORDS})", re.I)
_URGENT_PG = rf"\m({_URGENT_WORDS})"  # Postgres: \m = start of word (\b means backspace there)

# Voice formats browsers record: webm/opus (Chrome, Firefox), mp4/aac (Safari), ogg
_VOICE_MAGIC = {
    "webm": lambda b: b[:4] == b"\x1a\x45\xdf\xa3",
    "ogg": lambda b: b[:4] == b"OggS",
    "m4a": lambda b: b[4:8] == b"ftyp",
    "mp3": lambda b: b[:3] == b"ID3" or b[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"),
}


# ---------------- schemas ----------------
class SupportMsgOut(BaseModel):
    id: int
    sender: Literal["member", "bot", "staff"]
    staff_name: str | None
    kind: Literal["text", "photo", "voice"]
    body: str | None
    media_url: str | None
    duration_s: int | None
    meta: dict | None
    created_at: datetime


class TicketOut(BaseModel):
    id: str
    status: str
    subject: str | None
    created_at: datetime
    escalated_at: datetime | None


class SupportView(BaseModel):
    ticket: TicketOut | None
    messages: list[SupportMsgOut]
    welcome: str
    suggestions: list[dict]
    chat_muted_until: datetime | None


class SupportTextIn(BaseModel):
    body: str = Field(default="", max_length=2000)
    intent: str | None = Field(default=None, max_length=40)  # tapped suggestion chip


class FeedbackIn(BaseModel):
    message_id: int
    helpful: bool


# ---------------- helpers ----------------
async def _open_ticket(db: AsyncSession, user: User) -> SupportTicket | None:
    return await db.scalar(
        select(SupportTicket)
        .where(SupportTicket.user_id == user.id, SupportTicket.status != TicketStatus.CLOSED)
        .order_by(SupportTicket.created_at.desc())
        .limit(1)
    )


async def _staff_names(db: AsyncSession, msgs: list[SupportMessage]) -> dict:
    ids = {m.staff_id for m in msgs if m.staff_id}
    if not ids:
        return {}
    return dict((await db.execute(select(User.id, User.name).where(User.id.in_(ids)))).all())


def _out(m: SupportMessage, names: dict) -> SupportMsgOut:
    return SupportMsgOut(
        id=m.id,
        sender=m.sender,
        kind=m.kind,
        body=m.body,
        duration_s=m.duration_s,
        meta=m.meta,
        created_at=m.created_at,
        staff_name=(names.get(m.staff_id) or "Support team") if m.sender == "staff" else None,
        media_url=get_storage().signed_url(m.media_key) if m.media_key else None,
    )


def _ticket_out(t: SupportTicket) -> TicketOut:
    return TicketOut(
        id=str(t.id),
        status=t.status,
        subject=t.subject,
        created_at=t.created_at,
        escalated_at=t.escalated_at,
    )


async def _view(db: AsyncSession, user: User) -> SupportView:
    t = await _open_ticket(db, user)
    msgs = (
        list(
            await db.scalars(
                select(SupportMessage)
                .where(SupportMessage.ticket_id == t.id)
                .order_by(SupportMessage.id)
            )
        )
        if t
        else []
    )
    names = await _staff_names(db, msgs)
    return SupportView(
        ticket=_ticket_out(t) if t else None,
        messages=[_out(m, names) for m in msgs],
        welcome=WELCOME,
        suggestions=chips(["otp", "photos", "review", "matches", "chat", "safety", "talk"]),
        chat_muted_until=user.chat_muted_until,
    )


async def _actor(db: AsyncSession, user: User) -> str:
    pid = await db.scalar(select(Profile.public_id).where(Profile.user_id == user.id))
    return pid or (mask_phone(decrypt(user.phone_enc)) if user.phone_enc else str(user.id))


async def _escalate(
    db: AsyncSession,
    t: SupportTicket,
    user: User,
    request: Request | None,
    reason: str,
    urgent: bool = False,
) -> None:
    first = t.status not in (TicketStatus.WAITING,)
    t.status = TicketStatus.WAITING
    t.escalated_at = t.escalated_at or datetime.now(UTC)
    if first:
        await record_event(
            "support_escalated",
            category="support",
            level="error" if urgent else "info",
            actor=await _actor(db, user),
            actor_type="member",
            request=request,
            message=("URGENT — " if urgent else "") + f"Handed to team: {reason}",
            meta={"ticket": str(t.id)},
        )


async def _ensure_ticket(db: AsyncSession, user: User, subject: str | None) -> SupportTicket:
    t = await _open_ticket(db, user)
    if t is None:
        t = SupportTicket(user_id=user.id, subject=(subject or "Help request")[:160])
        db.add(t)
        await db.flush()
    return t


async def _push_member(user_id: uuid.UUID) -> None:
    await publish_account(user_id, {"type": "support"})


# ---------------- member endpoints ----------------
@router.get("/support", response_model=SupportView)
async def my_support(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    v = await _view(db, user)
    # mark team replies as read
    if v.ticket:
        await db.execute(
            SupportMessage.__table__.update()
            .where(
                SupportMessage.ticket_id == uuid.UUID(v.ticket.id),
                SupportMessage.sender != "member",
                SupportMessage.read_at.is_(None),
            )
            .values(read_at=datetime.now(UTC))
        )
        await db.commit()
    return v


@router.post("/support/messages", response_model=SupportView)
async def send_support(
    body: SupportTextIn,
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    text = body.body.strip()
    if not text and not body.intent:
        raise HTTPException(422, "Message is empty")
    if not await hit(get_redis(), f"rl:support:{user.id}", 15, 60):
        raise HTTPException(429, "You're sending messages too fast. Please slow down.")
    verdict = check_text(text)
    if not verdict.ok:
        await record_violation(db, user, "support", verdict.rule)
        await record_event(
            "vulgar_language_blocked",
            category="safety",
            level="warning",
            actor=await _actor(db, user),
            actor_type="member",
            request=request,
            message="Blocked in help chat",
        )
        raise HTTPException(422, VULGAR_MESSAGE)

    shown = text or (BY_KEY[body.intent].title if body.intent in BY_KEY else "")
    t = await _ensure_ticket(db, user, shown)
    now = datetime.now(UTC)
    db.add(
        SupportMessage(
            ticket_id=t.id,
            sender="member",
            body=shown,
            meta={"intent": body.intent} if body.intent else None,
        )
    )
    t.last_message_at = now

    if t.status in (TicketStatus.WAITING, TicketStatus.ANSWERED):
        # A person is handling this conversation: no bot replies, just notify the team
        t.status = TicketStatus.WAITING
    else:
        reply = answer(text, body.intent)
        urgent = bool(URGENT.search(text))
        db.add(
            SupportMessage(
                ticket_id=t.id,
                sender="bot",
                body=reply.text,
                meta={
                    "intent": reply.intent,
                    "suggestions": reply.suggestions,
                    "ask_feedback": reply.ask_feedback and not urgent,
                },
            )
        )
        t.topic = reply.intent or t.topic
        if reply.escalate or urgent:
            await _escalate(
                db, t, user, request, reply.intent or "assistant couldn't answer", urgent
            )
            if urgent and not reply.escalate:
                db.add(
                    SupportMessage(
                        ticket_id=t.id,
                        sender="bot",
                        body=(
                            "I've alerted our safety team, and a person will reply here as soon as possible. "
                            "If you are in immediate danger, please call 112."
                        ),
                    )
                )
    await db.commit()
    return await _view(db, user)


@router.post("/support/escalate", response_model=SupportView)
async def escalate(
    request: Request, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    t = await _ensure_ticket(db, user, "Asked for a person")
    if t.status != TicketStatus.WAITING:
        db.add(
            SupportMessage(
                ticket_id=t.id,
                sender="bot",
                body=(
                    "Okay — I've passed this to our support team. A team member will reply here, usually "
                    "within a few hours. Feel free to add details, a screenshot or a voice note."
                ),
            )
        )
        await _escalate(db, t, user, request, "member asked for a person")
        t.last_message_at = datetime.now(UTC)
        await db.commit()
    return await _view(db, user)


@router.post("/support/feedback", response_model=SupportView)
async def feedback(
    body: FeedbackIn,
    request: Request,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    m = await db.get(SupportMessage, body.message_id)
    t = await db.get(SupportTicket, m.ticket_id) if m else None
    if not m or not t or t.user_id != user.id or m.sender != "bot":
        raise HTTPException(404, "Message not found")
    m.meta = {**(m.meta or {}), "ask_feedback": False, "helpful": body.helpful}
    if body.helpful:
        db.add(
            SupportMessage(ticket_id=t.id, sender="bot", body="Glad that helped! 😊 Anything else?")
        )
    else:
        db.add(
            SupportMessage(
                ticket_id=t.id,
                sender="bot",
                body=(
                    "Sorry that didn't help. I've passed your question to our support team — a person will "
                    "reply here soon."
                ),
            )
        )
        await _escalate(db, t, user, request, f"answer not helpful ({m.meta.get('intent')})")
    t.last_message_at = datetime.now(UTC)
    await db.commit()
    return await _view(db, user)


@router.post("/support/attachments", response_model=SupportView)
async def attach(
    request: Request,
    kind: Literal["photo", "voice"] = Form(...),
    duration_s: int | None = Form(None),
    file: UploadFile = File(...),
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    """Screenshot/photo or voice note in the help chat. Always goes to the team."""
    if not await hit(get_redis(), f"rl:support:{user.id}", 15, 60):
        raise HTTPException(429, "You're sending messages too fast. Please slow down.")
    st = get_storage()
    mid = uuid.uuid4().hex
    if kind == "photo":
        data = await file.read(settings.MAX_PHOTO_BYTES + 1)
        if len(data) > settings.MAX_PHOTO_BYTES:
            raise HTTPException(413, "Photo must be under 10 MB")
        try:
            proc = images.process(data)  # validates + strips EXIF/GPS, re-encodes to WebP
        except images.ImageError as e:
            raise HTTPException(422, str(e)) from None
        key, payload, dur = f"support/{user.id}/{mid}.webp", proc.large, None
    else:
        data = await file.read(settings.VOICE_MAX_BYTES + 1)
        if len(data) > settings.VOICE_MAX_BYTES:
            raise HTTPException(413, "Voice note is too long (max 2 minutes)")
        ext = next((e for e, ok in _VOICE_MAGIC.items() if ok(data)), None)
        if ext is None:
            raise HTTPException(422, "That file isn't a supported voice recording")
        dur = max(1, min(int(duration_s or 1), settings.VOICE_MAX_SECONDS))
        key, payload = f"support/{user.id}/{mid}.{ext}", data

    t = await _ensure_ticket(db, user, "Screenshot" if kind == "photo" else "Voice note")
    st.save(key, payload)
    db.add(
        SupportMessage(ticket_id=t.id, sender="member", kind=kind, media_key=key, duration_s=dur)
    )
    t.last_message_at = datetime.now(UTC)
    if t.status != TicketStatus.WAITING:
        db.add(
            SupportMessage(
                ticket_id=t.id,
                sender="bot",
                body=(
                    "Thanks — I've attached that for our support team, and a person will look at it and reply here."
                ),
            )
        )
        await _escalate(
            db, t, user, request, f"member sent a {'photo' if kind == 'photo' else 'voice note'}"
        )
    await db.commit()
    return await _view(db, user)


@router.post("/support/close", response_model=SupportView)
async def close_mine(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    t = await _open_ticket(db, user)
    if t:
        t.status, t.closed_at = TicketStatus.CLOSED, datetime.now(UTC)
        await db.commit()
    return await _view(db, user)


# ---------------- translation fallback ----------------
class TranslateIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    target: str = Field(pattern=r"^[a-z]{2}(-[A-Z]{2})?$")


@router.post("/translate")
async def translate(body: TranslateIn, user: User = Depends(current_user)):
    """Used only when the browser can't translate on-device."""
    if not await hit(get_redis(), f"rl:translate:{user.id}", 60, 3600):
        raise HTTPException(429, "Translation limit reached for now")
    if settings.TRANSLATE_PROVIDER != "google" or not settings.GOOGLE_TRANSLATE_API_KEY:
        raise HTTPException(
            503,
            "Translation isn't available in this browser. Try Chrome (desktop) "
            "or enable server translation.",
        )
    import httpx

    async with httpx.AsyncClient(timeout=10) as c:
        r = await c.post(
            "https://translation.googleapis.com/language/translate/v2",
            params={"key": settings.GOOGLE_TRANSLATE_API_KEY},
            json={"q": body.text, "target": body.target, "format": "text"},
        )
    if r.status_code != 200:
        raise HTTPException(502, "Translation service error")
    d = r.json()["data"]["translations"][0]
    return {"text": d["translatedText"], "source": d.get("detectedSourceLanguage")}


# ---------------- staff: support inbox ----------------
class TicketRow(BaseModel):
    id: str
    status: str
    subject: str | None
    topic: str | None
    member: dict
    last_message: str | None
    last_message_at: datetime | None
    escalated_at: datetime | None
    unread: int
    urgent: bool


class TicketDetail(BaseModel):
    ticket: TicketRow
    messages: list[SupportMsgOut]


class StaffReplyIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    close: bool = False


async def _rows(db: AsyncSession, tickets: list[SupportTicket]) -> list[TicketRow]:
    if not tickets:
        return []
    ids = [t.id for t in tickets]
    users = {
        u.id: u
        for u in await db.scalars(select(User).where(User.id.in_([t.user_id for t in tickets])))
    }
    profs = {
        p.user_id: p
        for p in await db.scalars(select(Profile).where(Profile.user_id.in_(users.keys())))
    }
    unread = dict(
        (
            await db.execute(
                select(SupportMessage.ticket_id, func.count())
                .where(
                    SupportMessage.ticket_id.in_(ids),
                    SupportMessage.sender == "member",
                    SupportMessage.read_at.is_(None),
                )
                .group_by(SupportMessage.ticket_id)
            )
        ).all()
    )
    last = {}
    for m in await db.scalars(
        select(SupportMessage)
        .where(SupportMessage.ticket_id.in_(ids))
        .order_by(SupportMessage.id.desc())
    ):
        last.setdefault(m.ticket_id, m)
    urgent = {
        tid
        for (tid,) in (
            await db.execute(
                select(SupportMessage.ticket_id)
                .where(
                    SupportMessage.ticket_id.in_(ids),
                    SupportMessage.sender == "member",
                    SupportMessage.body.op("~*")(_URGENT_PG),
                )
                .distinct()
            )
        ).all()
    }
    out = []
    for t in tickets:
        u, p = users.get(t.user_id), profs.get(t.user_id)
        lm = last.get(t.id)
        preview = (
            lm.body
            if lm and lm.kind == "text"
            else ("📷 Photo" if lm and lm.kind == "photo" else "🎤 Voice note" if lm else None)
        )
        out.append(
            TicketRow(
                id=str(t.id),
                status=t.status,
                subject=t.subject,
                topic=t.topic,
                member={
                    "public_id": p.public_id if p else None,
                    "name": f"{p.first_name} {p.last_name or ''}".strip()
                    if p
                    else "No profile yet",
                    "phone": mask_phone(decrypt(u.phone_enc)) if u and u.phone_enc else None,
                    "status": p.status if p else None,
                    "chat_muted_until": u.chat_muted_until.isoformat()
                    if u and u.chat_muted_until
                    else None,
                },
                last_message=(preview or "")[:140] or None,
                last_message_at=t.last_message_at,
                escalated_at=t.escalated_at,
                unread=unread.get(t.id, 0),
                urgent=t.id in urgent,
            )
        )
    return out


@router.get("/admin/support", response_model=list[TicketRow], tags=["admin"])
async def inbox(
    status: Literal["waiting_team", "answered", "bot", "closed"] = "waiting_team",
    _: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    order = (
        SupportTicket.escalated_at.asc()
        if status == "waiting_team"
        else SupportTicket.last_message_at.desc()
    )
    tickets = list(
        await db.scalars(
            select(SupportTicket).where(SupportTicket.status == status).order_by(order).limit(200)
        )
    )
    return await _rows(db, tickets)


@router.get("/admin/support/{ticket_id}", response_model=TicketDetail, tags=["admin"])
async def inbox_ticket(
    ticket_id: uuid.UUID, _: User = Depends(current_staff), db: AsyncSession = Depends(get_db)
):
    t = await db.get(SupportTicket, ticket_id)
    if t is None:
        raise HTTPException(404, "Conversation not found")
    msgs = list(
        await db.scalars(
            select(SupportMessage)
            .where(SupportMessage.ticket_id == t.id)
            .order_by(SupportMessage.id)
        )
    )
    await db.execute(
        SupportMessage.__table__.update()
        .where(
            SupportMessage.ticket_id == t.id,
            SupportMessage.sender == "member",
            SupportMessage.read_at.is_(None),
        )
        .values(read_at=datetime.now(UTC))
    )
    await db.commit()
    names = await _staff_names(db, msgs)
    return TicketDetail(ticket=(await _rows(db, [t]))[0], messages=[_out(m, names) for m in msgs])


@router.post("/admin/support/{ticket_id}/reply", response_model=TicketDetail, tags=["admin"])
async def staff_reply(
    ticket_id: uuid.UUID,
    body: StaffReplyIn,
    request: Request,
    staff: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    t = await db.get(SupportTicket, ticket_id)
    if t is None:
        raise HTTPException(404, "Conversation not found")
    now = datetime.now(UTC)
    db.add(
        SupportMessage(ticket_id=t.id, sender="staff", staff_id=staff.id, body=body.body.strip())
    )
    t.status = TicketStatus.CLOSED if body.close else TicketStatus.ANSWERED
    t.assigned_to, t.last_message_at = staff.id, now
    if body.close:
        t.closed_at = now
    await db.commit()
    await record_event(
        "support_replied",
        category="support",
        actor=decrypt(staff.email_enc) if staff.email_enc else str(staff.id),
        actor_type="staff",
        request=request,
        message="Team replied" + (" and closed" if body.close else ""),
        meta={"ticket": str(t.id)},
    )
    await _push_member(t.user_id)
    return await inbox_ticket(ticket_id, staff, db)


@router.post("/admin/support/{ticket_id}/close", response_model=TicketDetail, tags=["admin"])
async def staff_close(
    ticket_id: uuid.UUID, staff: User = Depends(current_staff), db: AsyncSession = Depends(get_db)
):
    t = await db.get(SupportTicket, ticket_id)
    if t is None:
        raise HTTPException(404, "Conversation not found")
    t.status, t.closed_at = TicketStatus.CLOSED, datetime.now(UTC)
    await db.commit()
    await _push_member(t.user_id)
    return await inbox_ticket(ticket_id, staff, db)


@router.get("/admin/support-counts", tags=["admin"])
async def support_counts(_: User = Depends(current_staff), db: AsyncSession = Depends(get_db)):
    waiting = await db.scalar(
        select(func.count())
        .select_from(SupportTicket)
        .where(SupportTicket.status == "waiting_team")
    )
    return {"waiting_team": waiting or 0}
