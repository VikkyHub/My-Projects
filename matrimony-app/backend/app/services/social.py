"""Shared rules for how members see each other: viewer, blocks, privacy, profile cards.

Every endpoint that returns another member goes through `build_cards` so privacy rules
(name initial, photo visibility, hidden fields) live in exactly one place.
"""

import time
import uuid
from datetime import UTC, date, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Block,
    City,
    Community,
    Conversation,
    EducationLevel,
    Interest,
    MotherTongue,
    Occupation,
    Photo,
    PrivacySettings,
    Profile,
    ProfileCareer,
    Religion,
    Shortlist,
    State,
    User,
)
from app.models.profile import ProfileStatus
from app.services.profiles import age_on
from app.services.storage import get_storage

VIEWER_OK = {ProfileStatus.PENDING_REVIEW, ProfileStatus.ACTIVE}
IST = timedelta(hours=5, minutes=30)


# ---------------- viewer ----------------
async def get_viewer(db: AsyncSession, user: User) -> Profile:
    p = await db.scalar(select(Profile).where(Profile.user_id == user.id))
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Create your profile first")
    if p.status not in VIEWER_OK:
        msg = {
            ProfileStatus.DRAFT: "Your profile is waiting for the candidate's consent",
            ProfileStatus.SUSPENDED: "Your profile is suspended",
        }.get(p.status, "Your profile isn't active")
        raise HTTPException(status.HTTP_403_FORBIDDEN, msg)
    p.last_active_at = datetime.now(UTC)
    return p


def require_active(viewer: Profile, action: str) -> None:
    if viewer.status != ProfileStatus.ACTIVE:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            f"Your profile is under review — you can {action} once it's approved.",
        )


async def get_target(db: AsyncSession, viewer: Profile, public_id: str) -> Profile:
    t = await db.scalar(select(Profile).where(Profile.public_id == public_id))
    if t is None or (t.id != viewer.id and t.status != ProfileStatus.ACTIVE):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not found")
    if t.id != viewer.id and await is_blocked(db, viewer.id, t.id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not found")
    return t


def blocked_clause(viewer_id: uuid.UUID, other_col):
    """SQL: no block in either direction between viewer and other_col."""
    return (
        ~select(Block.blocker_id)
        .where(
            or_(
                and_(Block.blocker_id == viewer_id, Block.blocked_id == other_col),
                and_(Block.blocker_id == other_col, Block.blocked_id == viewer_id),
            )
        )
        .exists()
    )


async def is_blocked(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> bool:
    return bool(
        await db.scalar(
            select(Block.blocker_id).where(
                or_(
                    and_(Block.blocker_id == a, Block.blocked_id == b),
                    and_(Block.blocker_id == b, Block.blocked_id == a),
                )
            )
        )
    )


def ist_day_start_utc() -> datetime:
    now_ist = datetime.now(UTC) + IST
    return datetime(now_ist.year, now_ist.month, now_ist.day, tzinfo=UTC) - IST


# ---------------- master-data names (cached) ----------------
_lookup: dict | None = None
_lookup_at = 0.0


async def lookups(db: AsyncSession) -> dict:
    global _lookup, _lookup_at
    if _lookup is None or time.monotonic() - _lookup_at > 300:
        _lookup = {
            "religion": dict((await db.execute(select(Religion.id, Religion.name))).all()),
            "community": dict((await db.execute(select(Community.id, Community.name))).all()),
            "tongue": dict((await db.execute(select(MotherTongue.id, MotherTongue.name))).all()),
            "education": {
                r.id: (r.name, r.rank) for r in (await db.execute(select(EducationLevel))).scalars()
            },
            "occupation": dict((await db.execute(select(Occupation.id, Occupation.name))).all()),
            "city": {
                r.id: (r.name, r.state, r.state_id)
                for r in await db.execute(
                    select(City.id, City.name, State.name.label("state"), City.state_id).join(
                        State, State.id == City.state_id
                    )
                )
            },
        }
        _lookup_at = time.monotonic()
    return _lookup


# ---------------- photos ----------------
def photo_keys(profile_id: uuid.UUID, photo_id: uuid.UUID) -> dict[str, str]:
    base = f"photos/{profile_id}/{photo_id}"
    return {"lg": f"{base}_lg.webp", "sm": f"{base}_sm.webp", "blur": f"{base}_blur.webp"}


def can_see_photos(viewer: Profile, target: Profile, visibility: str, accepted: bool) -> bool:
    if viewer.id == target.id or visibility == "all":
        return True
    if visibility == "premium":
        return viewer.is_premium or accepted
    return accepted  # "accepted": only people whose interest was accepted


# ---------------- cards ----------------
def last_active_label(ts: datetime | None) -> str | None:
    if ts is None:
        return None
    d = datetime.now(UTC) - ts
    if d < timedelta(hours=1):
        return "Online recently"
    if d < timedelta(days=1):
        return "Active today"
    if d < timedelta(days=7):
        return "Active this week"
    return None


def display_name(target: Profile, viewer: Profile, accepted: bool) -> str:
    """Free members see only the last-name initial (unless the interest was accepted)."""
    if not target.last_name:
        return target.first_name
    if viewer.is_premium or accepted or viewer.id == target.id:
        return f"{target.first_name} {target.last_name}"
    return f"{target.first_name} {target.last_name[0]}."


async def relations(db: AsyncSession, viewer: Profile, ids: list[uuid.UUID]) -> dict:
    """Interest state, conversation and shortlist for many targets in 3 queries."""
    if not ids:
        return {"interest": {}, "conv": {}, "short": set()}
    rows = (
        await db.scalars(
            select(Interest)
            .where(
                or_(
                    and_(Interest.sender_id == viewer.id, Interest.receiver_id.in_(ids)),
                    and_(Interest.receiver_id == viewer.id, Interest.sender_id.in_(ids)),
                )
            )
            .order_by(Interest.created_at)
        )
    ).all()
    interest = {}
    for i in rows:  # later rows win -> latest interest per pair
        other = i.receiver_id if i.sender_id == viewer.id else i.sender_id
        interest[other] = i
    convs = (
        await db.execute(
            select(Conversation.id, Conversation.profile_a, Conversation.profile_b).where(
                or_(
                    and_(Conversation.profile_a == viewer.id, Conversation.profile_b.in_(ids)),
                    and_(Conversation.profile_b == viewer.id, Conversation.profile_a.in_(ids)),
                )
            )
        )
    ).all()
    conv = {(c.profile_b if c.profile_a == viewer.id else c.profile_a): c.id for c in convs}
    short = set(
        (
            await db.scalars(
                select(Shortlist.target_id).where(
                    Shortlist.owner_id == viewer.id, Shortlist.target_id.in_(ids)
                )
            )
        ).all()
    )
    return {"interest": interest, "conv": conv, "short": short}


def interest_view(i: Interest | None, viewer: Profile) -> dict | None:
    if i is None or i.status == "withdrawn":
        return None
    return {
        "id": str(i.id),
        "status": i.status,
        "direction": "sent" if i.sender_id == viewer.id else "received",
    }


async def build_cards(
    db: AsyncSession,
    viewer: Profile,
    targets: list[Profile],
    scores: dict[uuid.UUID, int] | None = None,
) -> list[dict]:
    if not targets:
        return []
    lk = await lookups(db)
    ids = [t.id for t in targets]
    rel = await relations(db, viewer, ids)
    careers = {
        c.profile_id: c
        for c in (await db.scalars(select(ProfileCareer).where(ProfileCareer.profile_id.in_(ids))))
    }
    privacy = {
        p.profile_id: p
        for p in (
            await db.scalars(select(PrivacySettings).where(PrivacySettings.profile_id.in_(ids)))
        )
    }
    primary = {
        ph.profile_id: ph
        for ph in (
            await db.scalars(
                select(Photo).where(
                    Photo.profile_id.in_(ids), Photo.status == "approved", Photo.is_primary
                )
            )
        )
    }
    storage = get_storage()
    viewer_city = lk["city"].get(viewer.city_id)
    out = []
    for t in targets:
        i = rel["interest"].get(t.id)
        accepted = i is not None and i.status == "accepted"
        car = careers.get(t.id)
        city = lk["city"].get(t.city_id)
        vis = privacy[t.id].photo_visibility if t.id in privacy else "all"
        ph = primary.get(t.id)
        photo, locked = None, False
        if ph:
            keys = photo_keys(t.id, ph.id)
            if can_see_photos(viewer, t, vis, accepted):
                photo = storage.signed_url(keys["sm"])
            else:
                photo, locked = storage.signed_url(keys["blur"]), True
        reasons = []
        if t.community_id and t.community_id == viewer.community_id:
            reasons.append("Same community")
        if t.mother_tongue_id and t.mother_tongue_id == viewer.mother_tongue_id:
            reasons.append(f"Speaks {lk['tongue'].get(t.mother_tongue_id)}")
        if city and viewer_city:
            if t.city_id == viewer.city_id:
                reasons.append(f"Lives in {city[0]}")
            elif city[2] == viewer_city[2]:
                reasons.append(f"From {city[1]}")
        if t.diet and t.diet == viewer.diet:
            reasons.append(
                {"veg": "Vegetarian too", "jain": "Jain diet too"}.get(t.diet, "Same diet")
            )
        out.append(
            {
                "public_id": t.public_id,
                "name": display_name(t, viewer, accepted),
                "first_name": t.first_name,
                "gender": t.gender,
                "age": age_on(t.dob),
                "height_cm": t.height_cm,
                "marital_status": t.marital_status,
                "religion": lk["religion"].get(t.religion_id),
                "community": lk["community"].get(t.community_id),
                "mother_tongue": lk["tongue"].get(t.mother_tongue_id),
                "city": city[0] if city else None,
                "state": city[1] if city else None,
                "education": lk["education"].get(car.education_level_id, (None,))[0]
                if car and car.education_level_id
                else None,
                "occupation": lk["occupation"].get(car.occupation_id) if car else None,
                "about": (t.about_me[:160] + "…")
                if t.about_me and len(t.about_me) > 160
                else t.about_me,
                "is_premium": t.is_premium,
                "created_by": t.created_by,
                "last_active": last_active_label(t.last_active_at),
                "photo_url": photo,
                "photo_locked": locked,
                "match_score": (scores or {}).get(t.id),
                "match_reasons": reasons[:3],
                "interest": interest_view(i, viewer),
                "conversation_id": str(rel["conv"][t.id]) if t.id in rel["conv"] else None,
                "shortlisted": t.id in rel["short"],
            }
        )
    return out


def age_bounds(age_min: int | None, age_max: int | None) -> tuple[date | None, date | None]:
    """Convert an age range to a dob range (dob_min, dob_max)."""
    today = date.today()

    def years_ago(n: int) -> date:
        try:
            return today.replace(year=today.year - n)
        except ValueError:  # 29 Feb
            return today.replace(year=today.year - n, day=28)

    dob_max = years_ago(age_min) if age_min else None  # youngest allowed
    dob_min = years_ago(age_max + 1) + timedelta(days=1) if age_max else None  # oldest allowed
    return dob_min, dob_max
