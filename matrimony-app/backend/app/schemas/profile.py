import re
from datetime import date, datetime, time
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.core.phone import InvalidPhone, normalize_phone

CreatedByT = Literal["self", "parent", "sibling", "relative", "friend"]
GenderT = Literal["male", "female"]
MaritalT = Literal["never_married", "divorced", "widowed", "awaiting_divorce"]
DietT = Literal["veg", "non_veg", "eggetarian", "vegan", "jain"]
HabitT = Literal["no", "occasionally", "yes"]

# Contact details / links in free text are the #1 way scammers bypass paid unlocks.
_PHONE_RE = re.compile(r"(?:\+?\d[\s\-.]?){10,}")
_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
_URL_RE = re.compile(r"(https?://|www\.|\b[\w-]+\.(com|in|net|org|me|io)\b)", re.I)
_BANNED_RE = re.compile(r"\b(dowry|dahej)\b", re.I)


def _check_free_text(v: str | None) -> str | None:
    if v is None:
        return v
    v = v.strip()
    if _PHONE_RE.search(v) or _EMAIL_RE.search(v) or _URL_RE.search(v):
        raise ValueError("Please don't include phone numbers, emails or links")
    if _BANNED_RE.search(v):
        raise ValueError("This content is not allowed")
    return v or None


def _clean_name(v: str | None) -> str | None:
    if v is None:
        return v
    v = " ".join(v.split())
    if not re.fullmatch(r"[A-Za-z][A-Za-z .'-]*", v):
        raise ValueError("Name may contain only letters, spaces, . ' -")
    return v.title()


class _Name(BaseModel):
    first_name: str = Field(min_length=1, max_length=60)
    last_name: str | None = Field(default=None, max_length=60)

    @field_validator("first_name", "last_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        return _clean_name(v)


class ProfileCreate(_Name):
    created_by: CreatedByT
    candidate_phone: str | None = Field(
        default=None, description="Required when created_by is not 'self'"
    )
    gender: GenderT
    dob: date
    marital_status: MaritalT = "never_married"
    has_children: bool | None = None
    height_cm: int | None = Field(default=None, ge=120, le=230)
    religion_id: int
    community_id: int | None = None
    sub_community_id: int | None = None
    mother_tongue_id: int | None = None
    city_id: int | None = None
    accept_terms: bool = Field(description="Must be true: Terms of Use + Privacy Policy")

    @field_validator("candidate_phone")
    @classmethod
    def _phone(cls, v: str | None) -> str | None:
        if v is None:
            return v
        try:
            return normalize_phone(v)
        except InvalidPhone as e:
            raise ValueError(str(e)) from e

    @model_validator(mode="after")
    def _rules(self) -> "ProfileCreate":
        if not self.accept_terms:
            raise ValueError("You must accept the Terms of Use and Privacy Policy")
        if self.created_by != "self" and not self.candidate_phone:
            raise ValueError("candidate_phone is required when creating a profile for someone else")
        if self.created_by == "self":
            self.candidate_phone = None
        if self.marital_status == "never_married":
            self.has_children = False
        if self.sub_community_id and not self.community_id:
            raise ValueError("sub_community_id requires community_id")
        return self


class FamilyIn(BaseModel):
    father_occupation: str | None = Field(default=None, max_length=100)
    mother_occupation: str | None = Field(default=None, max_length=100)
    brothers: int | None = Field(default=None, ge=0, le=20)
    brothers_married: int | None = Field(default=None, ge=0, le=20)
    sisters: int | None = Field(default=None, ge=0, le=20)
    sisters_married: int | None = Field(default=None, ge=0, le=20)
    family_type: Literal["joint", "nuclear"] | None = None
    family_status: Literal["middle", "upper_middle", "rich", "affluent"] | None = None
    family_values: Literal["traditional", "moderate", "liberal"] | None = None
    native_place: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def _married_le_total(self) -> "FamilyIn":
        if (self.brothers_married or 0) > (self.brothers or 0) and self.brothers is not None:
            raise ValueError("brothers_married cannot exceed brothers")
        if (self.sisters_married or 0) > (self.sisters or 0) and self.sisters is not None:
            raise ValueError("sisters_married cannot exceed sisters")
        return self


class CareerIn(BaseModel):
    education_level_id: int | None = None
    education_detail: str | None = Field(default=None, max_length=150)
    college: str | None = Field(default=None, max_length=150)
    occupation_id: int | None = None
    employer: str | None = Field(default=None, max_length=150)
    employed_in: Literal["private", "govt", "business", "self_employed", "not_working"] | None = (
        None
    )
    annual_income_band: int | None = Field(default=None, ge=0, le=15)


class HoroscopeIn(BaseModel):
    rashi: str | None = Field(default=None, max_length=30)
    nakshatra: str | None = Field(default=None, max_length=30)
    manglik: Literal["yes", "no", "anshik", "dont_know"] | None = None
    birth_time: time | None = None
    birth_place: str | None = Field(default=None, max_length=100)
    gotra: str | None = Field(default=None, max_length=60)
    visible_to: Literal["all", "premium", "accepted"] = "accepted"


class ProfileUpdate(BaseModel):
    """gender, dob and created_by are intentionally NOT editable (change via support)."""

    model_config = ConfigDict(extra="forbid")

    first_name: str | None = Field(default=None, min_length=1, max_length=60)
    last_name: str | None = Field(default=None, max_length=60)
    marital_status: MaritalT | None = None
    has_children: bool | None = None
    height_cm: int | None = Field(default=None, ge=120, le=230)
    religion_id: int | None = None
    community_id: int | None = None
    sub_community_id: int | None = None
    mother_tongue_id: int | None = None
    city_id: int | None = None
    diet: DietT | None = None
    smoke: HabitT | None = None
    drink: HabitT | None = None
    about_me: str | None = Field(default=None, max_length=1000)
    family: FamilyIn | None = None
    career: CareerIn | None = None
    horoscope: HoroscopeIn | None = None

    @field_validator("first_name", "last_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        return _clean_name(v)

    @field_validator("about_me")
    @classmethod
    def _about(cls, v: str | None) -> str | None:
        return _check_free_text(v)


class CandidateConsentVerifyIn(BaseModel):
    code: str = Field(pattern=r"^\d{4,8}$")


# ---------- output ----------
class _Orm(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class FamilyOut(_Orm, FamilyIn):
    pass


class CareerOut(_Orm, CareerIn):
    pass


class HoroscopeOut(_Orm, HoroscopeIn):
    pass


class PrivacyOut(_Orm):
    photo_visibility: str
    contact_visibility: str
    show_last_active: bool
    hidden_from_search: bool


class MyProfileOut(_Orm):
    """The owner's own view: everything, but phone numbers masked."""

    public_id: str
    created_by: str
    candidate_phone_masked: str | None = None
    candidate_consent_pending: bool
    first_name: str
    last_name: str | None
    gender: str
    dob: date
    age: int
    height_cm: int | None
    marital_status: str
    has_children: bool | None
    religion_id: int
    community_id: int | None
    sub_community_id: int | None
    mother_tongue_id: int | None
    city_id: int | None
    diet: str | None
    smoke: str | None
    drink: str | None
    about_me: str | None
    status: str
    moderation_note: str | None = None
    completeness: int
    is_premium: bool
    family: FamilyOut | None
    career: CareerOut | None
    horoscope: HoroscopeOut | None
    privacy: PrivacyOut | None
    created_at: datetime
