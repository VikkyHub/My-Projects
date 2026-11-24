import uuid
from datetime import date, datetime, time

from sqlalchemy import (
    ARRAY,
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    SmallInteger,
    String,
    Text,
    Time,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, created_at_col, updated_at_col, uuid_pk


class CreatedBy:
    SELF = "self"
    PARENT = "parent"
    SIBLING = "sibling"
    RELATIVE = "relative"
    FRIEND = "friend"
    ALL = (SELF, PARENT, SIBLING, RELATIVE, FRIEND)


class ProfileStatus:
    DRAFT = "draft"  # created, waiting for candidate consent
    PENDING_REVIEW = "pending_review"  # consented, waiting for moderator
    ACTIVE = "active"
    HIDDEN = "hidden"
    REJECTED = "rejected"
    SUSPENDED = "suspended"


class Profile(Base):
    """The bride / groom. 1:1 with the login account in the MVP."""

    __tablename__ = "profiles"
    __table_args__ = (
        Index(
            "ix_profiles_search",
            "status",
            "gender",
            "religion_id",
            "community_id",
            "dob",
            "height_cm",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    public_id: Mapped[str] = mapped_column(String(12), unique=True)  # "VM4K9X2Q"

    created_by: Mapped[str] = mapped_column(String(20))
    # Set for EVERY profile (for "self" it is the account phone). Unique => one profile per
    # candidate, so a parent and the candidate can't both create one.
    candidate_phone_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    candidate_phone_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    candidate_consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    first_name: Mapped[str] = mapped_column(String(60))
    last_name: Mapped[str | None] = mapped_column(String(60))
    gender: Mapped[str] = mapped_column(String(10))  # male | female
    dob: Mapped[date] = mapped_column(Date)
    height_cm: Mapped[int | None] = mapped_column(SmallInteger)
    marital_status: Mapped[str] = mapped_column(String(20))
    has_children: Mapped[bool | None] = mapped_column(Boolean)

    religion_id: Mapped[int] = mapped_column(ForeignKey("religions.id"))
    community_id: Mapped[int | None] = mapped_column(ForeignKey("communities.id"))
    sub_community_id: Mapped[int | None] = mapped_column(ForeignKey("sub_communities.id"))
    mother_tongue_id: Mapped[int | None] = mapped_column(ForeignKey("mother_tongues.id"))
    city_id: Mapped[int | None] = mapped_column(ForeignKey("cities.id"), index=True)

    diet: Mapped[str | None] = mapped_column(String(20))
    smoke: Mapped[str | None] = mapped_column(String(20))
    drink: Mapped[str | None] = mapped_column(String(20))
    about_me: Mapped[str | None] = mapped_column(Text)

    status: Mapped[str] = mapped_column(String(20), default=ProfileStatus.DRAFT)
    completeness: Mapped[int] = mapped_column(SmallInteger, default=0)
    is_premium: Mapped[bool] = mapped_column(Boolean, default=False)  # denormalized
    last_active_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()
    updated_at: Mapped[datetime] = updated_at_col()

    family: Mapped["ProfileFamily | None"] = relationship(lazy="selectin", uselist=False)
    career: Mapped["ProfileCareer | None"] = relationship(lazy="selectin", uselist=False)
    horoscope: Mapped["ProfileHoroscope | None"] = relationship(lazy="selectin", uselist=False)
    privacy: Mapped["PrivacySettings | None"] = relationship(lazy="selectin", uselist=False)


class ProfileFamily(Base):
    __tablename__ = "profile_family"
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    father_occupation: Mapped[str | None] = mapped_column(String(100))
    mother_occupation: Mapped[str | None] = mapped_column(String(100))
    brothers: Mapped[int | None] = mapped_column(SmallInteger)
    brothers_married: Mapped[int | None] = mapped_column(SmallInteger)
    sisters: Mapped[int | None] = mapped_column(SmallInteger)
    sisters_married: Mapped[int | None] = mapped_column(SmallInteger)
    family_type: Mapped[str | None] = mapped_column(String(20))  # joint | nuclear
    family_status: Mapped[str | None] = mapped_column(String(20))
    family_values: Mapped[str | None] = mapped_column(String(20))
    native_place: Mapped[str | None] = mapped_column(String(100))


class ProfileCareer(Base):
    __tablename__ = "profile_career"
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    education_level_id: Mapped[int | None] = mapped_column(ForeignKey("education_levels.id"))
    education_detail: Mapped[str | None] = mapped_column(String(150))
    college: Mapped[str | None] = mapped_column(String(150))
    occupation_id: Mapped[int | None] = mapped_column(ForeignKey("occupations.id"))
    employer: Mapped[str | None] = mapped_column(String(150))
    employed_in: Mapped[str | None] = mapped_column(String(20))
    annual_income_band: Mapped[int | None] = mapped_column(SmallInteger)  # never exact salary


class ProfileHoroscope(Base):
    __tablename__ = "profile_horoscope"
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    rashi: Mapped[str | None] = mapped_column(String(30))
    nakshatra: Mapped[str | None] = mapped_column(String(30))
    manglik: Mapped[str | None] = mapped_column(String(20))  # yes | no | anshik | dont_know
    birth_time: Mapped[time | None] = mapped_column(Time)
    birth_place: Mapped[str | None] = mapped_column(String(100))
    gotra: Mapped[str | None] = mapped_column(String(60))
    visible_to: Mapped[str] = mapped_column(String(20), default="accepted")


class Photo(Base):
    __tablename__ = "photos"
    id: Mapped[uuid.UUID] = uuid_pk()
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), index=True
    )
    storage_key: Mapped[str] = mapped_column(String(255))  # private bucket; signed URLs only
    phash: Mapped[int | None] = mapped_column(BigInteger, index=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    sort: Mapped[int] = mapped_column(SmallInteger, default=0)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    reject_reason: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = created_at_col()


class PrivacySettings(Base):
    __tablename__ = "privacy_settings"
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    photo_visibility: Mapped[str] = mapped_column(String(20), default="all")
    contact_visibility: Mapped[str] = mapped_column(String(20), default="premium_unlock")
    show_last_active: Mapped[bool] = mapped_column(Boolean, default=True)
    hidden_from_search: Mapped[bool] = mapped_column(Boolean, default=False)


class PartnerPreferences(Base):
    __tablename__ = "partner_preferences"
    __table_args__ = (Index("ix_pref_community_ids", "community_ids", postgresql_using="gin"),)
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    age_min: Mapped[int | None] = mapped_column(SmallInteger)
    age_max: Mapped[int | None] = mapped_column(SmallInteger)
    height_min_cm: Mapped[int | None] = mapped_column(SmallInteger)
    height_max_cm: Mapped[int | None] = mapped_column(SmallInteger)
    marital_statuses: Mapped[list[str] | None] = mapped_column(ARRAY(String(20)))
    religion_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    community_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    mother_tongue_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    city_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    state_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    country_ids: Mapped[list[int] | None] = mapped_column(ARRAY(Integer))
    min_education_rank: Mapped[int | None] = mapped_column(SmallInteger)
    min_income_band: Mapped[int | None] = mapped_column(SmallInteger)
    diets: Mapped[list[str] | None] = mapped_column(ARRAY(String(20)))
    manglik: Mapped[str | None] = mapped_column(String(20))


class Verification(Base):
    __tablename__ = "verifications"
    __table_args__ = (UniqueConstraint("profile_id", "type", name="uq_verification_profile_type"),)
    id: Mapped[uuid.UUID] = uuid_pk()
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE")
    )
    type: Mapped[str] = mapped_column(String(30))  # mobile|photo|aadhaar|pan|dl|selfie_liveness
    status: Mapped[str] = mapped_column(String(20), default="pending")
    provider: Mapped[str | None] = mapped_column(String(30))
    provider_ref: Mapped[str | None] = mapped_column(String(100))
    masked_id: Mapped[str | None] = mapped_column(String(30))  # "XXXX-XXXX-1234" ONLY
    verified_name: Mapped[str | None] = mapped_column(String(120))
    verified_yob: Mapped[int | None] = mapped_column(SmallInteger)
    verified_gender: Mapped[str | None] = mapped_column(String(10))
    name_match_score: Mapped[float | None] = mapped_column(Float)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_col()
