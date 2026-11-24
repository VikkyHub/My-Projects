from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    ENV: Literal["dev", "test", "prod"] = "dev"
    APP_NAME: str = "Matrimony"
    API_PREFIX: str = "/api/v1"

    DATABASE_URL: str = "postgresql+asyncpg://matri:matri@localhost:55432/matrimony"
    REDIS_URL: str = "redis://localhost:6379/0"

    JWT_SECRET: str = "dev-only-jwt-secret-change-me-0123456789"
    JWT_ALGORITHM: str = "HS256"
    PHONE_HASH_KEY: str = "dev-only-phone-hash-key-change-me"
    # base64-url encoded 32 bytes; this dev default must never be used in prod
    DATA_ENC_KEY: str = "ZGV2LW9ubHktZGF0YS1lbmMta2V5LTMyLWJ5dGVzISE="

    ACCESS_TOKEN_MINUTES: int = 15
    REFRESH_TOKEN_DAYS: int = 30
    # A rotated refresh token may be reused for this long (several tabs refreshing at once).
    # After that, reuse is treated as theft and the whole token family is revoked.
    REFRESH_REUSE_GRACE_SECONDS: int = 30
    # Staff (admin panel) sessions
    ADMIN_IDLE_MINUTES: int = 30
    ADMIN_SESSION_HOURS: int = 8
    ADMIN_MAX_FAILED_LOGINS: int = 5
    ADMIN_LOCKOUT_MINUTES: int = 15

    CORS_ORIGINS: list[str] = Field(default_factory=lambda: ["http://localhost:5173"])

    # OTP policy
    OTP_LENGTH: int = 6
    OTP_TTL_SECONDS: int = 300
    OTP_MAX_ATTEMPTS: int = 3
    OTP_RESEND_COOLDOWN_SECONDS: int = 30
    OTP_MAX_SENDS_PER_PHONE_PER_HOUR: int = 3
    OTP_MAX_SENDS_PER_IP_PER_HOUR: int = 10

    # DEV ONLY: new profiles and photos skip moderation (there's no admin panel yet).
    DEV_AUTO_APPROVE: bool = False

    # Business rules
    CHAT_REQUIRES_PREMIUM: bool = True  # chat needs an accepted interest + one premium side
    FREE_DAILY_INTERESTS: int = 5
    PREMIUM_DAILY_INTERESTS: int = 50
    MAX_PHOTOS: int = 6
    MAX_PHOTO_BYTES: int = 10 * 1024 * 1024
    PHOTO_URL_TTL_SECONDS: int = 600

    # Photo storage. "local" writes to MEDIA_DIR (dev). R2/S3 backend comes with deployment.
    STORAGE_BACKEND: Literal["local"] = "local"
    MEDIA_DIR: str = "media"

    # DEV ONLY: every OTP is this code (e.g. "123456"). Forbidden outside ENV=dev.
    DEV_FIXED_OTP: str = ""

    SMS_PROVIDER: Literal["console", "msg91"] = "console"
    MSG91_AUTH_KEY: str = ""
    MSG91_OTP_TEMPLATE_ID: str = ""

    TERMS_VERSION: str = "2026-12-01"
    PRIVACY_VERSION: str = "2026-12-01"

    # Legal minimum marriage age in India
    MIN_AGE_MALE: int = 21
    MIN_AGE_FEMALE: int = 18

    @model_validator(mode="after")
    def _prod_guard(self) -> "Settings":
        if self.ENV == "prod":
            for name in ("JWT_SECRET", "PHONE_HASH_KEY", "DATA_ENC_KEY"):
                val = getattr(self, name)
                if (
                    "dev-only" in val
                    or val == "change-me"
                    or val == Settings.model_fields[name].default
                ):
                    raise ValueError(f"{name} must be set to a real secret in prod")
            if self.DEV_AUTO_APPROVE:
                raise ValueError("DEV_AUTO_APPROVE must not be set in prod")
            if self.DEV_FIXED_OTP:
                raise ValueError("DEV_FIXED_OTP must not be set in prod")
            if self.SMS_PROVIDER == "console":
                raise ValueError("SMS_PROVIDER=console is not allowed in prod")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
