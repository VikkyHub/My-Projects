"""Matches, partner preferences, public profiles, shortlist, block & report."""

from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import Integer, and_, case, func, literal, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.api.deps import current_user
from app.db.session import get_db
from app.models import (
    Block,
    City,
    Conversation,
    EducationLevel,
    Interest,
    PartnerPreferences,
    Photo,
    PrivacySettings,
    Profile,
    ProfileCareer,
    ProfileView,
    Report,
    Shortlist,
    State,
    User,
)
from app.models.profile import ProfileStatus
from app.schemas.master import Option
from app.schemas.social import MatchPage, Preferences, ProfileCard, PublicProfile, ReportIn
from app.services.profiles import age_on
from app.services.social import (
    age_bounds,
    blocked_clause,
    build_cards,
    can_see_photos,
    get_target,
    get_viewer,
    lookups,
    photo_keys,
)
from app.services.storage import get_storage

router = APIRouter(tags=["matches"])
PAGE = 12
AUTO_HIDE_REPORTS = 3


def _any(arr_col, value):
    """Their preference list is empty/NULL (= any) or contains my value."""
    return or_(
        arr_col.is_(None),
        func.cardinality(arr_col) == 0,
        literal(value) == func.any(arr_col) if value is not None else literal(False),
    )


@router.get("/matches", response_model=MatchPage)
async def matches(
    mode: Literal["recommended", "all"] = "recommended",
    age_min: int | None = Query(None, ge=18, le=80),
    age_max: int | None = Query(None, ge=18, le=80),
    religion_id: int | None = None,
    community_id: int | None = None,
    mother_tongue_id: int | None = None,
    state_id: int | None = None,
    marital_status: str | None = None,
    with_photo: bool = False,
    cursor: str | None = None,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    """Recommended = two-way preference match (I fit theirs, they fit mine), ranked by a
    0-100 score. "all" = only the explicit filters. Keyset pagination on (score, id)."""
    me = await get_viewer(db, user)
    my_pref = await db.get(PartnerPreferences, me.id)
    my_career = await db.get(ProfileCareer, me.id)
    lk = await lookups(db)
    my_state = lk["city"].get(me.city_id, (None, None, None))[2]
    my_age = age_on(me.dob)
    my_edu_rank = (
        lk["education"].get(my_career.education_level_id, (None, None))[1]
        if my_career and my_career.education_level_id
        else None
    )

    P = aliased(Profile)
    PP = aliased(PartnerPreferences)
    PC = aliased(ProfileCareer)
    PV = aliased(PrivacySettings)
    PCity = aliased(City)
    PEdu = aliased(EducationLevel)

    conds = [
        P.status == ProfileStatus.ACTIVE,
        P.gender != me.gender,
        P.id != me.id,
        or_(PV.hidden_from_search.is_(None), PV.hidden_from_search.is_(False)),
        blocked_clause(me.id, P.id),
    ]

    # ---- explicit filters (both modes) ----
    dmin, dmax = age_bounds(age_min, age_max)
    if dmin:
        conds.append(P.dob >= dmin)
    if dmax:
        conds.append(P.dob <= dmax)
    for col, val in (
        (P.religion_id, religion_id),
        (P.community_id, community_id),
        (P.mother_tongue_id, mother_tongue_id),
        (PCity.state_id, state_id),
        (P.marital_status, marital_status),
    ):
        if val is not None:
            conds.append(col == val)
    if with_photo:
        conds.append(
            select(Photo.id).where(Photo.profile_id == P.id, Photo.status == "approved").exists()
        )

    # ---- two-way preferences ----
    if mode == "recommended":
        if my_pref:
            dmin, dmax = age_bounds(my_pref.age_min, my_pref.age_max)
            if dmin:
                conds.append(P.dob >= dmin)
            if dmax:
                conds.append(P.dob <= dmax)
            if my_pref.height_min_cm:
                conds.append(P.height_cm >= my_pref.height_min_cm)
            if my_pref.height_max_cm:
                conds.append(P.height_cm <= my_pref.height_max_cm)
            for col, vals in (
                (P.marital_status, my_pref.marital_statuses),
                (P.religion_id, my_pref.religion_ids),
                (P.community_id, my_pref.community_ids),
                (P.mother_tongue_id, my_pref.mother_tongue_ids),
                (PCity.state_id, my_pref.state_ids),
                (P.diet, my_pref.diets),
            ):
                if vals:
                    conds.append(col.in_(vals))
            if my_pref.min_education_rank:
                conds.append(PEdu.rank >= my_pref.min_education_rank)
            if my_pref.min_income_band is not None:
                conds.append(PC.annual_income_band >= my_pref.min_income_band)
        # ...and I must fit THEIR preferences
        conds += [
            or_(PP.age_min.is_(None), PP.age_min <= my_age),
            or_(PP.age_max.is_(None), PP.age_max >= my_age),
            or_(PP.height_min_cm.is_(None), literal(me.height_cm or 0) >= PP.height_min_cm),
            or_(PP.height_max_cm.is_(None), literal(me.height_cm or 999) <= PP.height_max_cm),
            _any(PP.marital_statuses, me.marital_status),
            _any(PP.religion_ids, me.religion_id),
            _any(PP.community_ids, me.community_id),
            _any(PP.mother_tongue_ids, me.mother_tongue_id),
            _any(PP.state_ids, my_state),
            _any(PP.diets, me.diet),
            or_(
                PP.min_education_rank.is_(None), literal(my_edu_rank or 0) >= PP.min_education_rank
            ),
        ]

    # ---- score (0-100) ----
    # Only score on fields the viewer actually has; comparing against NULL would
    # otherwise reward profiles that are *also* missing the field.
    zero = literal(0, Integer)
    terms = []
    if me.community_id:
        terms.append(case((P.community_id == me.community_id, 20), else_=0))
    if me.mother_tongue_id:
        terms.append(case((P.mother_tongue_id == me.mother_tongue_id, 15), else_=0))
    if me.city_id:
        city_whens = [(P.city_id == me.city_id, 20)]
        if my_state:
            city_whens.append((PCity.state_id == my_state, 10))
        terms.append(case(*city_whens, else_=0))
    if me.diet:
        terms.append(case((P.diet == me.diet, 10), (P.diet.is_(None), 5), else_=0))
    else:
        terms.append(literal(5, Integer))
    terms.append(case((P.last_active_at >= datetime.now(UTC) - timedelta(days=7), 10), else_=0))
    terms.append(case((P.completeness >= 70, 10), else_=0))
    min_rank = my_pref.min_education_rank if my_pref and my_pref.min_education_rank else 1
    terms.append(case((PEdu.rank >= min_rank, 15), else_=0))
    score = sum(terms, zero).label("score")

    q = (
        select(P, score)
        .outerjoin(PP, PP.profile_id == P.id)
        .outerjoin(PC, PC.profile_id == P.id)
        .outerjoin(PV, PV.profile_id == P.id)
        .outerjoin(PCity, PCity.id == P.city_id)
        .outerjoin(PEdu, PEdu.id == PC.education_level_id)
        .where(*conds)
    )
    if cursor:
        try:
            s, pid = cursor.split("_", 1)
            s = int(s)
        except ValueError:
            raise HTTPException(400, "Bad cursor") from None
        q = q.where(or_(score < s, and_(score == s, P.public_id > pid)))
    q = q.order_by(score.desc(), P.public_id).limit(PAGE + 1)

    rows = (await db.execute(q)).all()
    await db.commit()  # persist viewer last_active_at
    more = len(rows) > PAGE
    rows = rows[:PAGE]
    targets = [r[0] for r in rows]
    scores = {r[0].id: int(r[1]) for r in rows}
    cards = await build_cards(db, me, targets, scores)
    nxt = f"{int(rows[-1][1])}_{rows[-1][0].public_id}" if more and rows else None
    return MatchPage(items=cards, next_cursor=nxt)


# ---------------- preferences ----------------
@router.get("/profiles/me/preferences", response_model=Preferences)
async def get_preferences(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    me = await db.scalar(select(Profile).where(Profile.user_id == user.id))
    if me is None:
        raise HTTPException(404, "Create your profile first")
    pref = await db.get(PartnerPreferences, me.id)
    if pref is None:
        return Preferences()
    return Preferences.model_validate({k: getattr(pref, k) for k in Preferences.model_fields})


@router.put("/profiles/me/preferences", response_model=Preferences)
async def put_preferences(
    body: Preferences, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await db.scalar(select(Profile).where(Profile.user_id == user.id))
    if me is None:
        raise HTTPException(404, "Create your profile first")
    pref = await db.get(PartnerPreferences, me.id)
    if pref is None:
        pref = PartnerPreferences(profile_id=me.id)
        db.add(pref)
    for k, v in body.model_dump().items():
        setattr(pref, k, v)
    await db.commit()
    return body


@router.get("/master/states", response_model=list[Option], tags=["master data"])
async def states(db: AsyncSession = Depends(get_db)):
    return (await db.scalars(select(State).order_by(State.name))).all()


# ---------------- public profile ----------------
@router.get("/profiles/{public_id}", response_model=PublicProfile)
async def public_profile(
    public_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    t = await get_target(db, me, public_id)
    card = (await build_cards(db, me, [t]))[0]
    accepted = bool(card["interest"] and card["interest"]["status"] == "accepted")

    priv = await db.get(PrivacySettings, t.id)
    vis = priv.photo_visibility if priv else "all"
    photos = (
        await db.scalars(
            select(Photo)
            .where(Photo.profile_id == t.id, Photo.status == "approved")
            .order_by(Photo.is_primary.desc(), Photo.sort)
        )
    ).all()
    st = get_storage()
    show = can_see_photos(me, t, vis, accepted)
    urls = [st.signed_url(photo_keys(t.id, p.id)["lg" if show else "blur"]) for p in photos]

    lk = await lookups(db)
    career = None
    if t.career:
        career = {
            "education": lk["education"].get(t.career.education_level_id, (None,))[0]
            if t.career.education_level_id
            else None,
            "education_detail": t.career.education_detail,
            "college": t.career.college,
            "occupation": lk["occupation"].get(t.career.occupation_id),
            "employed_in": t.career.employed_in,
            "annual_income_band": t.career.annual_income_band,
            # employer intentionally omitted (hidden by default)
        }
    family = None
    if t.family:
        family = {
            k: getattr(t.family, k)
            for k in (
                "father_occupation",
                "mother_occupation",
                "brothers",
                "brothers_married",
                "sisters",
                "sisters_married",
                "family_type",
                "family_status",
                "family_values",
                "native_place",
            )
        }
    horoscope, h_locked = None, False
    if t.horoscope:
        hv = t.horoscope.visible_to
        allowed = me.id == t.id or hv == "all" or (hv == "premium" and me.is_premium) or accepted
        if allowed:
            horoscope = {
                "rashi": t.horoscope.rashi,
                "nakshatra": t.horoscope.nakshatra,
                "manglik": t.horoscope.manglik,
                "birth_time": t.horoscope.birth_time.strftime("%H:%M")
                if t.horoscope.birth_time
                else None,
                "birth_place": t.horoscope.birth_place,
                "gotra": t.horoscope.gotra,
            }
        else:
            h_locked = True

    # Record the view (once per viewer/target/day)
    if me.id != t.id:
        today = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
        seen = await db.scalar(
            select(ProfileView.id).where(
                ProfileView.viewer_id == me.id,
                ProfileView.viewed_id == t.id,
                ProfileView.created_at >= today,
            )
        )
        if not seen:
            db.add(ProfileView(viewer_id=me.id, viewed_id=t.id))
    await db.commit()

    return PublicProfile(
        **card,
        about_full=t.about_me,
        photos=urls,
        family=family,
        career=career,
        horoscope=horoscope,
        horoscope_locked=h_locked,
        diet=t.diet,
        smoke=t.smoke,
        drink=t.drink,
        has_children=t.has_children,
    )


# ---------------- shortlist ----------------
@router.get("/shortlist", response_model=list[ProfileCard])
async def shortlist(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    me = await get_viewer(db, user)
    targets = (
        await db.scalars(
            select(Profile)
            .join(Shortlist, Shortlist.target_id == Profile.id)
            .where(
                Shortlist.owner_id == me.id,
                Profile.status == ProfileStatus.ACTIVE,
                blocked_clause(me.id, Profile.id),
            )
            .order_by(Shortlist.created_at.desc())
        )
    ).all()
    await db.commit()
    return await build_cards(db, me, list(targets))


@router.put("/shortlist/{public_id}", status_code=204)
async def add_shortlist(
    public_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    t = await get_target(db, me, public_id)
    await db.execute(
        insert(Shortlist).values(owner_id=me.id, target_id=t.id).on_conflict_do_nothing()
    )
    await db.commit()


@router.delete("/shortlist/{public_id}", status_code=204)
async def remove_shortlist(
    public_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await get_viewer(db, user)
    t = await db.scalar(select(Profile).where(Profile.public_id == public_id))
    if t:
        s = await db.get(Shortlist, (me.id, t.id))
        if s:
            await db.delete(s)
    await db.commit()


# ---------------- block & report ----------------
@router.post("/profiles/{public_id}/block", status_code=204)
async def block(
    public_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    """Hides both people from each other everywhere and closes their conversation."""
    me = await get_viewer(db, user)
    t = await get_target(db, me, public_id)
    if t.id == me.id:
        raise HTTPException(422, "You can't block yourself")
    await db.execute(
        insert(Block).values(blocker_id=me.id, blocked_id=t.id).on_conflict_do_nothing()
    )
    pair = or_(
        and_(Conversation.profile_a == me.id, Conversation.profile_b == t.id),
        and_(Conversation.profile_a == t.id, Conversation.profile_b == me.id),
    )
    await db.execute(update(Conversation).where(pair).values(status="closed"))
    await db.execute(
        update(Interest)
        .where(
            or_(
                and_(Interest.sender_id == me.id, Interest.receiver_id == t.id),
                and_(Interest.sender_id == t.id, Interest.receiver_id == me.id),
            ),
            Interest.status == "pending",
        )
        .values(status="withdrawn")
    )
    await db.execute(
        Shortlist.__table__.delete().where(
            or_(
                and_(Shortlist.owner_id == me.id, Shortlist.target_id == t.id),
                and_(Shortlist.owner_id == t.id, Shortlist.target_id == me.id),
            )
        )
    )
    await db.commit()
    from app.services.realtime import publish  # avoid import cycle at module load

    await publish(t.id, {"type": "refresh"})


@router.post("/profiles/{public_id}/report", status_code=204)
async def report(
    public_id: str,
    body: ReportIn,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await get_viewer(db, user)
    t = await db.scalar(select(Profile).where(Profile.public_id == public_id))
    if t is None or t.id == me.id:
        raise HTTPException(404, "Profile not found")
    already = await db.scalar(
        select(Report.id).where(
            Report.reporter_id == me.id, Report.reported_id == t.id, Report.status == "open"
        )
    )
    if not already:
        db.add(
            Report(
                reporter_id=me.id,
                reported_id=t.id,
                reason=body.reason,
                details=body.details,
                message_id=body.message_id,
            )
        )
        await db.flush()
    # Auto-hide after reports from several different members, pending moderator review
    distinct = await db.scalar(
        select(func.count(func.distinct(Report.reporter_id))).where(
            Report.reported_id == t.id, Report.status == "open"
        )
    )
    if distinct >= AUTO_HIDE_REPORTS and t.status == ProfileStatus.ACTIVE:
        t.status = ProfileStatus.PENDING_REVIEW
    await db.commit()
