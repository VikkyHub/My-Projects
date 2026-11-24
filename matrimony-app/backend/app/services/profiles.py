from datetime import UTC, date, datetime

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import decrypt, encrypt, hmac_hash, mask_phone, new_public_id
from app.models import (
    City,
    Community,
    Consent,
    EducationLevel,
    MotherTongue,
    Occupation,
    PartnerPreferences,
    PrivacySettings,
    Profile,
    ProfileCareer,
    ProfileFamily,
    ProfileHoroscope,
    Religion,
    SubCommunity,
    User,
)
from app.models.profile import CreatedBy, ProfileStatus
from app.schemas.profile import MyProfileOut, ProfileCreate, ProfileUpdate


class ProfileError(Exception):
    def __init__(self, message: str, status_code: int = 422) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _after_consent_status() -> str:
    """Moderation queue, or straight to live when DEV_AUTO_APPROVE is on (dev only)."""
    return ProfileStatus.ACTIVE if settings.DEV_AUTO_APPROVE else ProfileStatus.PENDING_REVIEW


def age_on(dob: date, today: date | None = None) -> int:
    today = today or date.today()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def check_age(gender: str, dob: date) -> None:
    age = age_on(dob)
    minimum = settings.MIN_AGE_MALE if gender == "male" else settings.MIN_AGE_FEMALE
    if age < minimum:
        raise ProfileError(f"Minimum age for {gender} candidates is {minimum} years")
    if age > 80:
        raise ProfileError("Please check the date of birth")


async def _validate_refs(
    db: AsyncSession,
    *,
    religion_id: int | None,
    community_id: int | None,
    sub_community_id: int | None,
    mother_tongue_id: int | None = None,
    city_id: int | None = None,
) -> None:
    """Community must belong to the religion; sub-community to the community."""
    if religion_id is not None and not await db.get(Religion, religion_id):
        raise ProfileError("Unknown religion")
    if community_id is not None:
        c = await db.get(Community, community_id)
        if c is None or c.religion_id != religion_id:
            raise ProfileError("Community does not belong to the selected religion")
    if sub_community_id is not None:
        sc = await db.get(SubCommunity, sub_community_id)
        if sc is None or sc.community_id != community_id:
            raise ProfileError("Sub-community does not belong to the selected community")
    if mother_tongue_id is not None and not await db.get(MotherTongue, mother_tongue_id):
        raise ProfileError("Unknown mother tongue")
    if city_id is not None and not await db.get(City, city_id):
        raise ProfileError("Unknown city")


def compute_completeness(p: Profile, photo_count: int = 0) -> int:
    checks = [
        bool(p.first_name),
        bool(p.dob),
        bool(p.religion_id),
        bool(p.community_id),
        bool(p.mother_tongue_id),
        bool(p.city_id),
        bool(p.height_cm),
        bool(p.diet),
        bool(p.about_me and len(p.about_me) >= 50),
        bool(p.family and (p.family.father_occupation or p.family.family_type)),
        bool(p.career and p.career.education_level_id),
        bool(p.career and p.career.occupation_id),
        bool(p.career and p.career.annual_income_band is not None),
        photo_count > 0,
    ]
    weights = [5, 5, 10, 5, 5, 10, 5, 5, 10, 10, 10, 10, 5, 5]  # sums to 100
    return sum(w for ok, w in zip(checks, weights, strict=True) if ok)


async def _unique_public_id(db: AsyncSession) -> str:
    for _ in range(10):
        pid = new_public_id()
        if not await db.scalar(select(exists().where(Profile.public_id == pid))):
            return pid
    raise RuntimeError("could not allocate public id")


async def create_profile(
    db: AsyncSession, user: User, data: ProfileCreate, ip: str | None
) -> Profile:
    if await db.scalar(select(exists().where(Profile.user_id == user.id))):
        raise ProfileError("This account already has a profile", 409)

    check_age(data.gender, data.dob)
    await _validate_refs(
        db,
        religion_id=data.religion_id,
        community_id=data.community_id,
        sub_community_id=data.sub_community_id,
        mother_tongue_id=data.mother_tongue_id,
        city_id=data.city_id,
    )

    is_self = data.created_by == CreatedBy.SELF
    if is_self:
        cand_hash, cand_enc = user.phone_hash, user.phone_enc
    else:
        cand_hash = hmac_hash(data.candidate_phone)
        if cand_hash == user.phone_hash:
            raise ProfileError(
                "The candidate's number is the same as yours. Choose 'Myself' if this is "
                "your own profile, or enter the candidate's own mobile number."
            )
        cand_enc = encrypt(data.candidate_phone)

    if await db.scalar(select(exists().where(Profile.candidate_phone_hash == cand_hash))):
        raise ProfileError("A profile already exists for this candidate", 409)

    now = datetime.now(UTC)
    profile = Profile(
        user_id=user.id,
        public_id=await _unique_public_id(db),
        created_by=data.created_by,
        candidate_phone_hash=cand_hash,
        candidate_phone_enc=cand_enc,
        # Profile stays hidden (draft) until the candidate personally consents.
        candidate_consent_at=now if is_self else None,
        status=(_after_consent_status() if is_self else ProfileStatus.DRAFT),
        first_name=data.first_name,
        last_name=data.last_name,
        gender=data.gender,
        dob=data.dob,
        height_cm=data.height_cm,
        marital_status=data.marital_status,
        has_children=data.has_children,
        religion_id=data.religion_id,
        community_id=data.community_id,
        sub_community_id=data.sub_community_id,
        mother_tongue_id=data.mother_tongue_id,
        city_id=data.city_id,
        last_active_at=now,
    )
    profile.privacy = PrivacySettings()
    # Mark optional sections as loaded-and-empty (avoids async lazy-load on a new object)
    profile.family = None
    profile.career = None
    profile.horoscope = None
    db.add(profile)
    await db.flush()
    db.add(PartnerPreferences(profile_id=profile.id))

    db.add_all(
        [
            Consent(
                user_id=user.id,
                purpose="terms",
                version=settings.TERMS_VERSION,
                granted=True,
                ip=ip,
            ),
            Consent(
                user_id=user.id,
                purpose="privacy",
                version=settings.PRIVACY_VERSION,
                granted=True,
                ip=ip,
            ),
        ]
    )
    if is_self:
        db.add(
            Consent(
                user_id=user.id,
                purpose="candidate_consent",
                version=settings.PRIVACY_VERSION,
                granted=True,
                ip=ip,
            )
        )

    profile.completeness = compute_completeness(profile)
    await db.commit()
    await db.refresh(profile)
    return profile


async def get_my_profile(db: AsyncSession, user: User) -> Profile | None:
    return await db.scalar(select(Profile).where(Profile.user_id == user.id))


async def update_profile(db: AsyncSession, profile: Profile, data: ProfileUpdate) -> Profile:
    fields = data.model_dump(exclude_unset=True, exclude={"family", "career", "horoscope"})

    ref_keys = {"religion_id", "community_id", "sub_community_id", "mother_tongue_id", "city_id"}
    if ref_keys & fields.keys():
        religion_id = fields.get("religion_id", profile.religion_id)
        if religion_id is None:
            raise ProfileError("religion_id cannot be empty")
        # Changing the parent clears the child unless a new child is given too.
        if religion_id != profile.religion_id and "community_id" not in fields:
            community_id = None
        else:
            community_id = fields.get("community_id", profile.community_id)
        if community_id != profile.community_id and "sub_community_id" not in fields:
            sub_id = None
        else:
            sub_id = fields.get("sub_community_id", profile.sub_community_id)
        await _validate_refs(
            db,
            religion_id=religion_id,
            community_id=community_id,
            sub_community_id=sub_id,
            mother_tongue_id=fields.get("mother_tongue_id"),
            city_id=fields.get("city_id"),
        )
        fields.update(religion_id=religion_id, community_id=community_id, sub_community_id=sub_id)

    if "first_name" in fields and not fields["first_name"]:
        raise ProfileError("first_name cannot be empty")

    for k, v in fields.items():
        setattr(profile, k, v)
    if profile.marital_status == "never_married":
        profile.has_children = False

    if data.career is not None:
        c = data.career
        if c.education_level_id and not await db.get(EducationLevel, c.education_level_id):
            raise ProfileError("Unknown education level")
        if c.occupation_id and not await db.get(Occupation, c.occupation_id):
            raise ProfileError("Unknown occupation")

    for attr, model, payload in (
        ("family", ProfileFamily, data.family),
        ("career", ProfileCareer, data.career),
        ("horoscope", ProfileHoroscope, data.horoscope),
    ):
        if payload is None:
            continue
        values = payload.model_dump(exclude_unset=True)
        section = getattr(profile, attr)
        if section is None:
            section = model(profile_id=profile.id)
            setattr(profile, attr, section)
        for k, v in values.items():
            setattr(section, k, v)

    if profile.status == ProfileStatus.REJECTED:
        # Member fixed what moderation asked for -> back into the review queue
        profile.status = _after_consent_status()
    profile.completeness = compute_completeness(profile, await photo_count(db, profile.id))
    await db.commit()
    await db.refresh(profile)
    return profile


async def photo_count(db: AsyncSession, profile_id) -> int:
    from sqlalchemy import func

    from app.models import Photo

    return (
        await db.scalar(
            select(func.count())
            .select_from(Photo)
            .where(Photo.profile_id == profile_id, Photo.status != "rejected")
        )
    ) or 0


async def confirm_candidate_consent(db: AsyncSession, profile: Profile, ip: str | None) -> None:
    profile.candidate_consent_at = datetime.now(UTC)
    if profile.status == ProfileStatus.DRAFT:
        profile.status = _after_consent_status()
    db.add(
        Consent(
            user_id=profile.user_id,
            purpose="candidate_consent",
            version=settings.PRIVACY_VERSION,
            granted=True,
            ip=ip,
        )
    )
    await db.commit()


def to_my_profile_out(p: Profile) -> MyProfileOut:
    masked = mask_phone(decrypt(p.candidate_phone_enc)) if p.candidate_phone_enc else None
    return MyProfileOut.model_validate(
        {
            **{c.key: getattr(p, c.key) for c in Profile.__table__.columns},
            "age": age_on(p.dob),
            "candidate_phone_masked": masked,
            "candidate_consent_pending": p.candidate_consent_at is None,
            "family": p.family,
            "career": p.career,
            "horoscope": p.horoscope,
            "privacy": p.privacy,
        }
    )
