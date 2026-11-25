"""Admin panel API. Every endpoint requires a staff token (password + TOTP login).
Every state change is written to admin_actions (who, what, when, why).

Moderators: review profiles/photos/reports, warn, suspend, reveal a phone (logged).
Admins: everything above + ban, reactivate banned accounts, manage staff, audit log.
"""

import math
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import current_admin, current_staff
from app.core.security import decrypt, encrypt, hash_password, hmac_hash, mask_phone
from app.db.session import get_db
from app.models import (
    AdminAction,
    AppEvent,
    Conversation,
    Interest,
    Message,
    Photo,
    Profile,
    RefreshToken,
    Report,
    SupportTicket,
    User,
)
from app.models.profile import ProfileStatus
from app.models.user import UserRole, UserStatus
from app.schemas.admin import (
    ActionRow,
    AdminPhoto,
    AppEventRow,
    LogPage,
    LogSummary,
    ModerateIn,
    PhotoActionIn,
    PhotoQueueItem,
    ProfileDetail,
    ProfilePage,
    ProfileRow,
    ReportRow,
    ResolveIn,
    RevealIn,
    StaffCreate,
    StaffCreated,
    StaffRow,
    Stats,
)
from app.services.profiles import age_on
from app.services.realtime import publish
from app.services.social import ist_day_start_utc, lookups, photo_keys
from app.services.storage import get_storage

router = APIRouter(prefix="/admin", tags=["admin"])
PAGE = 25


def log(db: AsyncSession, staff: User, ttype: str, tid: str, action: str, reason: str | None):
    db.add(
        AdminAction(
            admin_id=staff.id, target_type=ttype, target_id=tid, action=action, reason=reason
        )
    )


async def _profile(db: AsyncSession, public_id: str) -> Profile:
    p = await db.scalar(select(Profile).where(Profile.public_id == public_id))
    if p is None:
        raise HTTPException(404, "Profile not found")
    return p


# ---------------- dashboard ----------------
@router.get("/stats", response_model=Stats)
async def stats(_: User = Depends(current_staff), db: AsyncSession = Depends(get_db)):
    today = ist_day_start_utc()

    async def n(q):
        return (await db.scalar(q)) or 0

    member = Profile.user_id.is_not(None)
    return Stats(
        members_total=await n(select(func.count()).select_from(Profile).where(member)),
        signups_today=await n(
            select(func.count()).select_from(Profile).where(Profile.created_at >= today)
        ),
        signups_7d=await n(
            select(func.count())
            .select_from(Profile)
            .where(Profile.created_at >= today - timedelta(days=6))
        ),
        profiles_live=await n(
            select(func.count()).select_from(Profile).where(Profile.status == "active")
        ),
        profiles_pending=await n(
            select(func.count()).select_from(Profile).where(Profile.status == "pending_review")
        ),
        photos_pending=await n(
            select(func.count()).select_from(Photo).where(Photo.status == "pending")
        ),
        reports_open=await n(
            select(func.count()).select_from(Report).where(Report.status == "open")
        ),
        premium_members=await n(
            select(func.count()).select_from(Profile).where(Profile.is_premium)
        ),
        interests_today=await n(
            select(func.count()).select_from(Interest).where(Interest.created_at >= today)
        ),
        support_waiting=await n(
            select(func.count())
            .select_from(SupportTicket)
            .where(SupportTicket.status == "waiting_team")
        ),
        messages_today=await n(
            select(func.count()).select_from(Message).where(Message.created_at >= today)
        ),
    )


# ---------------- profiles ----------------
async def _rows(db: AsyncSession, profiles: list[Profile]) -> list[ProfileRow]:
    if not profiles:
        return []
    ids = [p.id for p in profiles]
    lk = await lookups(db)
    ph = dict(
        (r[0], (r[1], r[2]))
        for r in await db.execute(
            select(
                Photo.profile_id,
                func.count().filter(Photo.status == "pending"),
                func.count().filter(Photo.status != "rejected"),
            )
            .where(Photo.profile_id.in_(ids))
            .group_by(Photo.profile_id)
        )
    )
    rep = dict(
        (
            await db.execute(
                select(Report.reported_id, func.count())
                .where(Report.reported_id.in_(ids), Report.status == "open")
                .group_by(Report.reported_id)
            )
        ).all()
    )
    users = dict(
        (
            await db.execute(
                select(User.id, User.status).where(User.id.in_([p.user_id for p in profiles]))
            )
        ).all()
    )
    out = []
    for p in profiles:
        city = lk["city"].get(p.city_id)
        out.append(
            ProfileRow(
                public_id=p.public_id,
                name=f"{p.first_name} {p.last_name or ''}".strip(),
                gender=p.gender,
                age=age_on(p.dob),
                religion=lk["religion"].get(p.religion_id),
                community=lk["community"].get(p.community_id),
                city=f"{city[0]}, {city[1]}" if city else None,
                created_by=p.created_by,
                status=p.status,
                account_status=users.get(p.user_id, "?"),
                completeness=p.completeness,
                photos_pending=ph.get(p.id, (0, 0))[0],
                photos_total=ph.get(p.id, (0, 0))[1],
                reports_open=rep.get(p.id, 0),
                is_premium=p.is_premium,
                created_at=p.created_at,
                moderation_note=p.moderation_note,
            )
        )
    return out


@router.get("/profiles", response_model=ProfilePage)
async def list_profiles(
    status: str | None = Query(
        None, pattern="^(draft|pending_review|active|rejected|suspended|hidden)$"
    ),
    q: str | None = Query(None, max_length=60),
    page: int = Query(1, ge=1),
    _: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    conds = []
    if status:
        conds.append(Profile.status == status)
    if q:
        like = f"%{q.strip()}%"
        conds.append(
            or_(
                Profile.public_id.ilike(like),
                Profile.first_name.ilike(like),
                Profile.last_name.ilike(like),
                func.concat(Profile.first_name, " ", Profile.last_name).ilike(like),
            )
        )
    total = (await db.scalar(select(func.count()).select_from(Profile).where(*conds))) or 0
    # Oldest first in the review queue (fairness); newest first elsewhere
    order = Profile.created_at.asc() if status == "pending_review" else Profile.created_at.desc()
    profiles = (
        await db.scalars(
            select(Profile).where(*conds).order_by(order).offset((page - 1) * PAGE).limit(PAGE)
        )
    ).all()
    return ProfilePage(
        items=await _rows(db, list(profiles)),
        total=total,
        page=page,
        pages=max(1, math.ceil(total / PAGE)),
    )


def _admin_photo(p: Photo) -> AdminPhoto:
    return AdminPhoto(
        id=str(p.id),
        url=get_storage().signed_url(photo_keys(p.profile_id, p.id)["lg"]),
        status=p.status,
        is_primary=p.is_primary,
        duplicate=p.reject_reason == "duplicate_of_other_profile",
        created_at=p.created_at,
    )


async def _report_rows(db: AsyncSession, reports: list[Report]) -> list[ReportRow]:
    if not reports:
        return []
    pids = {r.reporter_id for r in reports} | {r.reported_id for r in reports}
    profs = {p.id: p for p in await db.scalars(select(Profile).where(Profile.id.in_(pids)))}
    msgs = {
        m.id: m.body
        for m in await db.scalars(
            select(Message).where(Message.id.in_([r.message_id for r in reports if r.message_id]))
        )
    }
    open_counts = dict(
        (
            await db.execute(
                select(Report.reported_id, func.count())
                .where(
                    Report.reported_id.in_([r.reported_id for r in reports]),
                    Report.status == "open",
                )
                .group_by(Report.reported_id)
            )
        ).all()
    )

    def mini(pid):
        p = profs.get(pid)
        return (
            {
                "public_id": p.public_id,
                "name": f"{p.first_name} {p.last_name or ''}".strip(),
                "status": p.status,
            }
            if p
            else {"public_id": "?", "name": "Deleted", "status": "deleted"}
        )

    return [
        ReportRow(
            id=str(r.id),
            reason=r.reason,
            details=r.details,
            status=r.status,
            created_at=r.created_at,
            reporter=mini(r.reporter_id),
            reported=mini(r.reported_id),
            message=msgs.get(r.message_id),
            reported_open_reports=open_counts.get(r.reported_id, 0),
        )
        for r in reports
    ]


async def _history(db: AsyncSession, target_ids: list[str], limit: int = 30) -> list[ActionRow]:
    rows = (
        await db.execute(
            select(AdminAction, User.name)
            .join(User, User.id == AdminAction.admin_id)
            .where(AdminAction.target_id.in_(target_ids))
            .order_by(AdminAction.id.desc())
            .limit(limit)
        )
    ).all()
    return [
        ActionRow(
            id=a.id,
            staff=name or "Staff",
            action=a.action,
            target_type=a.target_type,
            target_id=a.target_id,
            reason=a.reason,
            created_at=a.created_at,
        )
        for a, name in rows
    ]


@router.get("/profiles/{public_id}", response_model=ProfileDetail)
async def profile_detail(
    public_id: str, _: User = Depends(current_staff), db: AsyncSession = Depends(get_db)
):
    p = await _profile(db, public_id)
    row = (await _rows(db, [p]))[0]
    lk = await lookups(db)
    photos = (
        await db.scalars(select(Photo).where(Photo.profile_id == p.id).order_by(Photo.created_at))
    ).all()
    reports = (
        await db.scalars(
            select(Report).where(Report.reported_id == p.id).order_by(Report.created_at.desc())
        )
    ).all()

    def dump(obj, skip=("profile_id",)):
        if obj is None:
            return None
        return {
            c.key: (str(getattr(obj, c.key)) if getattr(obj, c.key) is not None else None)
            for c in obj.__table__.columns
            if c.key not in skip
        }

    career = dump(p.career)
    if career:
        career["education"] = (
            lk["education"].get(p.career.education_level_id, (None,))[0]
            if p.career.education_level_id
            else None
        )
        career["occupation"] = lk["occupation"].get(p.career.occupation_id)
    return ProfileDetail(
        **row.model_dump(),
        phone_masked=mask_phone(decrypt(p.candidate_phone_enc)) if p.candidate_phone_enc else None,
        consent_pending=p.candidate_consent_at is None,
        dob=p.dob.isoformat(),
        height_cm=p.height_cm,
        marital_status=p.marital_status,
        mother_tongue=lk["tongue"].get(p.mother_tongue_id),
        about_me=p.about_me,
        family=dump(p.family),
        career=career,
        horoscope=dump(p.horoscope),
        photos=[_admin_photo(x) for x in photos],
        reports=await _report_rows(db, list(reports)),
        history=await _history(
            db, [p.public_id, *[str(x.id) for x in photos], *[str(r.id) for r in reports]]
        ),
    )


async def _lock_out(db: AsyncSession, p: Profile, user_status: str) -> None:
    """Suspend/ban: block login, end sessions, close chats, cancel pending interests."""
    u = await db.get(User, p.user_id)
    u.status = user_status
    p.status = ProfileStatus.SUSPENDED
    now = datetime.now(UTC)
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now, revoked_reason="logout")
    )
    await db.execute(
        update(Conversation)
        .where(or_(Conversation.profile_a == p.id, Conversation.profile_b == p.id))
        .values(status="closed")
    )
    await db.execute(
        update(Interest)
        .where(
            or_(Interest.sender_id == p.id, Interest.receiver_id == p.id),
            Interest.status == "pending",
        )
        .values(status="withdrawn", responded_at=now)
    )


async def apply_moderation(
    db: AsyncSession, staff: User, p: Profile, action: str, reason: str | None
):
    if action in ("reject", "suspend", "ban") and not reason:
        raise HTTPException(
            422, "Please give a reason — it's recorded and (for reject) shown to the member"
        )
    if action == "ban" and staff.role != UserRole.ADMIN:
        raise HTTPException(403, "Only admins can ban members")
    u = await db.get(User, p.user_id)

    if action == "approve":
        if p.candidate_consent_at is None:
            raise HTTPException(409, "The candidate hasn't given consent yet")
        if u.status != UserStatus.ACTIVE:
            raise HTTPException(409, "Account is suspended/banned — reactivate it first")
        p.status, p.moderation_note = ProfileStatus.ACTIVE, None
    elif action == "reject":
        p.status, p.moderation_note = ProfileStatus.REJECTED, reason
    elif action == "suspend":
        await _lock_out(db, p, UserStatus.SUSPENDED)
        p.moderation_note = reason
    elif action == "ban":
        await _lock_out(db, p, UserStatus.BANNED)
        p.moderation_note = reason
    elif action == "reactivate":
        if u.status == UserStatus.BANNED and staff.role != UserRole.ADMIN:
            raise HTTPException(403, "Only admins can lift a ban")
        u.status = UserStatus.ACTIVE
        p.status, p.moderation_note = ProfileStatus.ACTIVE, None
    log(db, staff, "profile", p.public_id, action, reason)


@router.post("/profiles/{public_id}/moderate", response_model=ProfileRow)
async def moderate(
    public_id: str,
    body: ModerateIn,
    staff: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    p = await _profile(db, public_id)
    await apply_moderation(db, staff, p, body.action, body.reason)
    await db.commit()
    await publish(p.id, {"type": "refresh"})
    return (await _rows(db, [p]))[0]


@router.post("/profiles/{public_id}/reveal-phone")
async def reveal_phone(
    public_id: str,
    body: RevealIn,
    staff: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    """Phone numbers are masked everywhere in the panel; revealing one is logged with a reason."""
    p = await _profile(db, public_id)
    if not p.candidate_phone_enc:
        raise HTTPException(404, "No phone on file")
    log(db, staff, "profile", p.public_id, "reveal_phone", body.reason)
    await db.commit()
    return {"phone": decrypt(p.candidate_phone_enc)}


# ---------------- photos ----------------
@router.get("/photos", response_model=list[PhotoQueueItem])
async def photo_queue(
    status: str = Query("pending", pattern="^(pending|approved|rejected)$"),
    _: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(Photo, Profile)
            .join(Profile, Profile.id == Photo.profile_id)
            .where(Photo.status == status)
            .order_by(Photo.created_at.asc() if status == "pending" else Photo.created_at.desc())
            .limit(120)
        )
    ).all()
    return [
        PhotoQueueItem(
            **_admin_photo(ph).model_dump(),
            profile={
                "public_id": p.public_id,
                "name": f"{p.first_name} {p.last_name or ''}".strip(),
                "gender": p.gender,
                "age": age_on(p.dob),
                "status": p.status,
            },
        )
        for ph, p in rows
    ]


@router.post("/photos/{photo_id}/moderate", response_model=AdminPhoto)
async def moderate_photo(
    photo_id: uuid.UUID,
    body: PhotoActionIn,
    staff: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    ph = await db.get(Photo, photo_id)
    if ph is None:
        raise HTTPException(404, "Photo not found")
    if body.action == "reject" and not body.reason:
        raise HTTPException(422, "Please give a reason")
    ph.status = "approved" if body.action == "approve" else "rejected"
    ph.reject_reason = None if body.action == "approve" else body.reason
    if body.action == "reject" and ph.is_primary:
        ph.is_primary = False
        nxt = await db.scalar(
            select(Photo)
            .where(Photo.profile_id == ph.profile_id, Photo.id != ph.id, Photo.status != "rejected")
            .order_by(Photo.sort)
        )
        if nxt:
            nxt.is_primary = True
    log(db, staff, "photo", str(ph.id), f"photo_{body.action}", body.reason)
    await db.commit()
    await publish(ph.profile_id, {"type": "refresh"})
    return _admin_photo(ph)


# ---------------- reports ----------------
@router.get("/reports", response_model=list[ReportRow])
async def reports(
    status: str = Query("open", pattern="^(open|closed)$"),
    _: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    cond = Report.status == "open" if status == "open" else Report.status != "open"
    rows = (
        await db.scalars(
            select(Report)
            .where(cond)
            .order_by(Report.created_at.asc() if status == "open" else Report.resolved_at.desc())
            .limit(200)
        )
    ).all()
    return await _report_rows(db, list(rows))


@router.post("/reports/{report_id}/resolve", response_model=ReportRow)
async def resolve(
    report_id: uuid.UUID,
    body: ResolveIn,
    staff: User = Depends(current_staff),
    db: AsyncSession = Depends(get_db),
):
    r = await db.get(Report, report_id)
    if r is None:
        raise HTTPException(404, "Report not found")
    if r.status != "open":
        raise HTTPException(409, "Already resolved")
    p = await db.get(Profile, r.reported_id)
    now = datetime.now(UTC)
    if body.action in ("suspend", "ban"):
        await apply_moderation(db, staff, p, body.action, body.note or f"Report: {r.reason}")
    elif body.action == "warn":
        p.moderation_note = (
            body.note or f"Warning after a report ({r.reason}). Please follow community rules."
        )
        log(db, staff, "profile", p.public_id, "warn", body.note)

    # Close every open report about this member when we act on them; only this one on dismiss
    targets = (
        [r]
        if body.action == "dismiss"
        else (
            await db.scalars(
                select(Report).where(Report.reported_id == p.id, Report.status == "open")
            )
        ).all()
    )
    for t in targets:
        t.status = "dismissed" if body.action == "dismiss" else "actioned"
        t.resolved_by, t.resolved_at = staff.id, now
    log(db, staff, "report", str(r.id), f"report_{body.action}", body.note)

    # A profile auto-hidden by reports goes back live once nothing is left open
    if body.action in ("dismiss", "warn") and p.status == ProfileStatus.PENDING_REVIEW:
        remaining = await db.scalar(
            select(func.count())
            .select_from(Report)
            .where(Report.reported_id == p.id, Report.status == "open")
        )
        if not remaining and p.candidate_consent_at:
            p.status = ProfileStatus.ACTIVE
    await db.commit()
    await publish(p.id, {"type": "refresh"})
    return (await _report_rows(db, [r]))[0]


# ---------------- audit ----------------
@router.get("/audit", response_model=list[ActionRow])
async def audit(
    page: int = Query(1, ge=1),
    _: User = Depends(current_admin),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(AdminAction, User.name)
            .join(User, User.id == AdminAction.admin_id)
            .order_by(AdminAction.id.desc())
            .offset((page - 1) * 50)
            .limit(50)
        )
    ).all()
    return [
        ActionRow(
            id=a.id,
            staff=name or "Staff",
            action=a.action,
            target_type=a.target_type,
            target_id=a.target_id,
            reason=a.reason,
            created_at=a.created_at,
        )
        for a, name in rows
    ]


# ---------------- staff ----------------
def _staff_row(u: User) -> StaffRow:
    return StaffRow(
        id=str(u.id),
        name=u.name,
        email=decrypt(u.email_enc) if u.email_enc else None,
        role=u.role,
        status=u.status,
        totp_enabled=u.totp_enabled_at is not None,
        last_login_at=u.last_login_at,
        created_at=u.created_at,
    )


def temp_password() -> str:
    return secrets.token_urlsafe(9) + "7a"  # always letters + digits


@router.get("/staff", response_model=list[StaffRow])
async def staff_list(_: User = Depends(current_admin), db: AsyncSession = Depends(get_db)):
    rows = await db.scalars(
        select(User)
        .where(User.role.in_((UserRole.MODERATOR, UserRole.ADMIN)))
        .order_by(User.created_at)
    )
    return [_staff_row(u) for u in rows]


@router.post("/staff", response_model=StaffCreated, status_code=201)
async def staff_create(
    body: StaffCreate, me: User = Depends(current_admin), db: AsyncSession = Depends(get_db)
):
    email = body.email.strip().lower()
    if await db.scalar(select(User.id).where(User.email_hash == hmac_hash(email))):
        raise HTTPException(409, "An account with this email already exists")
    pw = temp_password()
    u = User(
        email_hash=hmac_hash(email),
        email_enc=encrypt(email),
        name=body.name.strip(),
        role=body.role,
        password_hash=hash_password(pw),
        must_change_password=True,
    )
    db.add(u)
    await db.flush()
    log(db, me, "staff", str(u.id), f"staff_create_{body.role}", email)
    await db.commit()
    await db.refresh(u)
    return StaffCreated(staff=_staff_row(u), temporary_password=pw)


async def _other_staff(db: AsyncSession, me: User, staff_id: uuid.UUID) -> User:
    u = await db.get(User, staff_id)
    if u is None or u.role not in (UserRole.MODERATOR, UserRole.ADMIN):
        raise HTTPException(404, "Staff member not found")
    if u.id == me.id:
        raise HTTPException(422, "You can't change your own staff account here")
    return u


@router.post("/staff/{staff_id}/disable", response_model=StaffRow)
async def staff_disable(
    staff_id: uuid.UUID, me: User = Depends(current_admin), db: AsyncSession = Depends(get_db)
):
    u = await _other_staff(db, me, staff_id)
    u.status = UserStatus.SUSPENDED
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC), revoked_reason="logout")
    )
    log(db, me, "staff", str(u.id), "staff_disable", None)
    await db.commit()
    return _staff_row(u)


@router.post("/staff/{staff_id}/enable", response_model=StaffRow)
async def staff_enable(
    staff_id: uuid.UUID, me: User = Depends(current_admin), db: AsyncSession = Depends(get_db)
):
    u = await _other_staff(db, me, staff_id)
    u.status = UserStatus.ACTIVE
    log(db, me, "staff", str(u.id), "staff_enable", None)
    await db.commit()
    return _staff_row(u)


@router.post("/staff/{staff_id}/reset", response_model=StaffCreated)
async def staff_reset(
    staff_id: uuid.UUID, me: User = Depends(current_admin), db: AsyncSession = Depends(get_db)
):
    """New temporary password AND new authenticator setup (e.g. lost phone)."""
    u = await _other_staff(db, me, staff_id)
    pw = temp_password()
    u.password_hash, u.must_change_password = hash_password(pw), True
    u.totp_secret_enc, u.totp_enabled_at = None, None
    u.failed_logins, u.locked_until = 0, None
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == u.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC), revoked_reason="logout")
    )
    log(db, me, "staff", str(u.id), "staff_reset", None)
    await db.commit()
    return StaffCreated(staff=_staff_row(u), temporary_password=pw)


# ---------------- application log (admin only: contains IP addresses) ----------------
FAILED_LOGIN_EVENTS = ("otp_failed", "staff_login_failed", "staff_2fa_failed")


@router.get("/logs", response_model=LogPage)
async def app_logs(
    level: str | None = Query(None, pattern="^(info|warning|error)$"),
    category: str | None = Query(
        None, pattern="^(auth|staff|profile|photo|interest|chat|safety|support|system)$"
    ),
    actor: str | None = Query(None, max_length=120),
    q: str | None = Query(None, max_length=80),
    before_id: int | None = None,
    limit: int = Query(100, ge=1, le=200),
    _: User = Depends(current_admin),
    db: AsyncSession = Depends(get_db),
):
    conds = []
    if level == "warning":  # "warnings" view also shows errors
        conds.append(AppEvent.level.in_(("warning", "error")))
    elif level:
        conds.append(AppEvent.level == level)
    if category:
        conds.append(AppEvent.category == category)
    if actor:
        conds.append(AppEvent.actor == actor.strip())
    if q:
        like = f"%{q.strip()}%"
        conds.append(
            or_(
                AppEvent.event.ilike(like),
                AppEvent.message.ilike(like),
                AppEvent.actor.ilike(like),
                AppEvent.request_id == q.strip(),
                func.host(AppEvent.ip) == q.strip(),
            )
        )
    if before_id:
        conds.append(AppEvent.id < before_id)
    rows = (
        await db.scalars(
            select(AppEvent).where(*conds).order_by(AppEvent.id.desc()).limit(limit + 1)
        )
    ).all()
    more = len(rows) > limit
    rows = rows[:limit]
    return LogPage(
        items=[
            AppEventRow(
                id=r.id,
                created_at=r.created_at,
                level=r.level,
                category=r.category,
                event=r.event,
                actor_type=r.actor_type,
                actor=r.actor,
                message=r.message,
                ip=str(r.ip) if r.ip else None,
                user_agent=r.user_agent,
                request_id=r.request_id,
                meta=r.meta,
            )
            for r in rows
        ],
        next_before_id=rows[-1].id if more and rows else None,
    )


@router.get("/logs/summary", response_model=LogSummary)
async def app_logs_summary(_: User = Depends(current_admin), db: AsyncSession = Depends(get_db)):
    since = datetime.now(UTC) - timedelta(hours=24)
    recent = AppEvent.created_at >= since
    row = (
        await db.execute(
            select(
                func.count(),
                func.count().filter(AppEvent.level == "warning"),
                func.count().filter(AppEvent.level == "error"),
                func.count().filter(AppEvent.event.in_(FAILED_LOGIN_EVENTS)),
                func.count().filter(AppEvent.event.in_(("member_login", "member_signup"))),
                func.count().filter(AppEvent.event.in_(("staff_login", "staff_2fa_setup"))),
            ).where(recent)
        )
    ).one()
    cats = dict(
        (
            await db.execute(
                select(AppEvent.category, func.count()).where(recent).group_by(AppEvent.category)
            )
        ).all()
    )
    return LogSummary(
        events_24h=row[0],
        warnings_24h=row[1],
        errors_24h=row[2],
        failed_logins_24h=row[3],
        member_logins_24h=row[4],
        staff_logins_24h=row[5],
        by_category=cats,
    )
