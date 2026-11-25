from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator


def _strong(v: str) -> str:
    if len(v) < 10 or not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
        raise ValueError("Use at least 10 characters with letters and numbers")
    return v


class StaffLoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=200)


class StaffLoginOut(BaseModel):
    step: Literal["totp", "enroll"]
    ticket: str
    must_change_password: bool
    otpauth_uri: str | None = None  # only for "enroll"
    secret: str | None = None  # only for "enroll" (manual entry)


class StaffVerifyIn(BaseModel):
    ticket: str
    code: str = Field(pattern=r"^\d{6}$")
    new_password: str | None = Field(default=None, max_length=200)

    @field_validator("new_password")
    @classmethod
    def _pw(cls, v):
        return _strong(v) if v is not None else v


class StaffMe(BaseModel):
    id: str
    name: str | None
    email: str | None
    role: str


class StaffTokens(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    staff: StaffMe


class Stats(BaseModel):
    members_total: int
    signups_today: int
    signups_7d: int
    profiles_live: int
    profiles_pending: int
    photos_pending: int
    reports_open: int
    premium_members: int
    interests_today: int
    messages_today: int


class ProfileRow(BaseModel):
    public_id: str
    name: str
    gender: str
    age: int
    religion: str | None
    community: str | None
    city: str | None
    created_by: str
    status: str
    account_status: str
    completeness: int
    photos_pending: int
    photos_total: int
    reports_open: int
    is_premium: bool
    created_at: datetime
    moderation_note: str | None


class ProfilePage(BaseModel):
    items: list[ProfileRow]
    total: int
    page: int
    pages: int


class AdminPhoto(BaseModel):
    id: str
    url: str
    status: str
    is_primary: bool
    duplicate: bool
    created_at: datetime


class ReportRow(BaseModel):
    id: str
    reason: str
    details: str | None
    status: str
    created_at: datetime
    reporter: dict
    reported: dict
    message: str | None
    reported_open_reports: int


class ActionRow(BaseModel):
    id: int
    staff: str
    action: str
    target_type: str
    target_id: str
    reason: str | None
    created_at: datetime


class ProfileDetail(ProfileRow):
    phone_masked: str | None
    consent_pending: bool
    dob: str
    height_cm: int | None
    marital_status: str
    mother_tongue: str | None
    about_me: str | None
    family: dict | None
    career: dict | None
    horoscope: dict | None
    photos: list[AdminPhoto]
    reports: list[ReportRow]
    history: list[ActionRow]


class ModerateIn(BaseModel):
    action: Literal["approve", "reject", "suspend", "ban", "reactivate"]
    reason: str | None = Field(default=None, max_length=300)


class RevealIn(BaseModel):
    reason: str = Field(min_length=5, max_length=300)


class PhotoQueueItem(AdminPhoto):
    profile: dict


class PhotoActionIn(BaseModel):
    action: Literal["approve", "reject"]
    reason: str | None = Field(default=None, max_length=200)


class ResolveIn(BaseModel):
    action: Literal["dismiss", "warn", "suspend", "ban"]
    note: str | None = Field(default=None, max_length=300)


class StaffRow(BaseModel):
    id: str
    name: str | None
    email: str | None
    role: str
    status: str
    totp_enabled: bool
    last_login_at: datetime | None
    created_at: datetime


class StaffCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=80)
    role: Literal["moderator", "admin"] = "moderator"


class StaffCreated(BaseModel):
    staff: StaffRow
    temporary_password: str  # shown ONCE; they must change it on first login


class AppEventRow(BaseModel):
    id: int
    created_at: datetime
    level: str
    category: str
    event: str
    actor_type: str | None
    actor: str | None
    message: str | None
    ip: str | None
    user_agent: str | None
    request_id: str | None
    meta: dict | None


class LogPage(BaseModel):
    items: list[AppEventRow]
    next_before_id: int | None


class LogSummary(BaseModel):
    events_24h: int
    warnings_24h: int
    errors_24h: int
    failed_logins_24h: int
    member_logins_24h: int
    staff_logins_24h: int
    by_category: dict[str, int]
