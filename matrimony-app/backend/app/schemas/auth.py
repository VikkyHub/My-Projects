from pydantic import BaseModel, Field, field_validator

from app.core.phone import InvalidPhone, normalize_phone


class PhoneIn(BaseModel):
    phone: str = Field(examples=["+919876543210", "9876543210"])

    @field_validator("phone")
    @classmethod
    def _normalize(cls, v: str) -> str:
        try:
            return normalize_phone(v)
        except InvalidPhone as e:
            raise ValueError(str(e)) from e


class OtpSendOut(BaseModel):
    message: str = "OTP sent"
    expires_in: int
    resend_after: int


class OtpVerifyIn(PhoneIn):
    code: str = Field(pattern=r"^\d{4,8}$")
    device_id: str | None = Field(default=None, max_length=100)


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class LoginOut(TokenOut):
    is_new_user: bool
    has_profile: bool


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)
