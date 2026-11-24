from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.profile import _check_free_text


class InterestRef(BaseModel):
    id: str
    status: str
    direction: Literal["sent", "received"]


class ProfileCard(BaseModel):
    public_id: str
    name: str
    first_name: str
    gender: str
    age: int
    height_cm: int | None
    marital_status: str
    religion: str | None
    community: str | None
    mother_tongue: str | None
    city: str | None
    state: str | None
    education: str | None
    occupation: str | None
    about: str | None
    is_premium: bool
    created_by: str
    last_active: str | None
    photo_url: str | None
    photo_locked: bool
    match_score: int | None
    match_reasons: list[str]
    interest: InterestRef | None
    conversation_id: str | None
    shortlisted: bool


class MatchPage(BaseModel):
    items: list[ProfileCard]
    next_cursor: str | None
    total_hint: int | None = None


MaritalT = Literal["never_married", "divorced", "widowed", "awaiting_divorce"]
DietT = Literal["veg", "non_veg", "eggetarian", "vegan", "jain"]


class Preferences(BaseModel):
    age_min: int | None = Field(default=None, ge=18, le=80)
    age_max: int | None = Field(default=None, ge=18, le=80)
    height_min_cm: int | None = Field(default=None, ge=120, le=230)
    height_max_cm: int | None = Field(default=None, ge=120, le=230)
    marital_statuses: list[MaritalT] | None = None
    religion_ids: list[int] | None = None
    community_ids: list[int] | None = None
    mother_tongue_ids: list[int] | None = None
    state_ids: list[int] | None = None
    min_education_rank: int | None = Field(default=None, ge=0, le=5)
    min_income_band: int | None = Field(default=None, ge=0, le=15)
    diets: list[DietT] | None = None

    @field_validator(
        "marital_statuses",
        "religion_ids",
        "community_ids",
        "mother_tongue_ids",
        "state_ids",
        "diets",
    )
    @classmethod
    def _empty_is_any(cls, v):
        return v or None  # [] means "any"

    @model_validator(mode="after")
    def _ranges(self) -> "Preferences":
        if self.age_min and self.age_max and self.age_min > self.age_max:
            raise ValueError("Minimum age can't be more than maximum age")
        if self.height_min_cm and self.height_max_cm and self.height_min_cm > self.height_max_cm:
            raise ValueError("Minimum height can't be more than maximum height")
        return self


class PublicProfile(ProfileCard):
    about_full: str | None
    photos: list[str]
    family: dict | None
    career: dict | None
    horoscope: dict | None
    horoscope_locked: bool
    diet: str | None
    smoke: str | None
    drink: str | None
    has_children: bool | None


class InterestCreate(BaseModel):
    public_id: str
    note: str | None = Field(default=None, max_length=300)

    @field_validator("note")
    @classmethod
    def _note(cls, v):
        return _check_free_text(v)


class InterestItem(BaseModel):
    id: str
    status: str
    direction: Literal["sent", "received"]
    note: str | None
    created_at: datetime
    responded_at: datetime | None
    profile: ProfileCard


class InterestCounts(BaseModel):
    received_pending: int
    unread_messages: int
    sent_today: int
    daily_limit: int


class ReportIn(BaseModel):
    reason: Literal[
        "fake", "harassment", "married", "scam_money", "dowry", "obscene", "underage", "other"
    ]
    details: str | None = Field(default=None, max_length=1000)
    message_id: int | None = None


class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    id: int
    conversation_id: str
    sender_public_id: str
    body: str
    flagged: bool
    created_at: datetime
    read_at: datetime | None


class ConversationItem(BaseModel):
    id: str
    profile: ProfileCard
    last_message: str | None
    last_message_at: datetime | None
    last_from_me: bool
    unread: int
    can_chat: bool
    blocked_reason: Literal["premium_required", "closed"] | None


class PhotoOut(BaseModel):
    id: str
    url: str
    status: str
    is_primary: bool


class PhotoSettings(BaseModel):
    photo_visibility: Literal["all", "premium", "accepted"]
