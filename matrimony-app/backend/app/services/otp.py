"""OTP issue/verify backed by Redis.

Keys (phone is always the HMAC hash, never plaintext):
  otp:{purpose}:{phone_hash}          hash {code_hash, attempts}   TTL = OTP_TTL_SECONDS
  otp:cooldown:{purpose}:{phone_hash} "1"                          TTL = resend cooldown
  rl:otp:phone:{phone_hash}           counter                      TTL = 1h
  rl:otp:ip:{ip}                      counter                      TTL = 1h
"""

from dataclasses import dataclass

from redis.asyncio import Redis

from app.core.config import settings
from app.core.security import constant_time_equals, generate_otp, hmac_hash, sha256
from app.services.rate_limit import hit
from app.services.sms import SmsProvider


class OtpError(Exception):
    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


@dataclass
class OtpSent:
    expires_in: int
    resend_after: int


def _key(purpose: str, phone_hash: str) -> str:
    return f"otp:{purpose}:{phone_hash}"


async def send_otp(
    redis: Redis, sms: SmsProvider, phone_e164: str, purpose: str, ip: str | None
) -> OtpSent:
    ph = hmac_hash(phone_e164)

    if await redis.exists(f"otp:cooldown:{purpose}:{ph}"):
        raise OtpError("Please wait before requesting another OTP", 429)
    if ip and not await hit(redis, f"rl:otp:ip:{ip}", settings.OTP_MAX_SENDS_PER_IP_PER_HOUR, 3600):
        raise OtpError("Too many OTP requests. Try again later.", 429)
    if not await hit(redis, f"rl:otp:phone:{ph}", settings.OTP_MAX_SENDS_PER_PHONE_PER_HOUR, 3600):
        raise OtpError("Too many OTP requests for this number. Try again in an hour.", 429)

    code = generate_otp(settings.OTP_LENGTH)
    key = _key(purpose, ph)
    pipe = redis.pipeline()
    pipe.delete(key)
    pipe.hset(key, mapping={"code_hash": sha256(code), "attempts": 0})
    pipe.expire(key, settings.OTP_TTL_SECONDS)
    pipe.set(f"otp:cooldown:{purpose}:{ph}", "1", ex=settings.OTP_RESEND_COOLDOWN_SECONDS)
    await pipe.execute()

    await sms.send_otp(phone_e164, code)
    return OtpSent(settings.OTP_TTL_SECONDS, settings.OTP_RESEND_COOLDOWN_SECONDS)


async def verify_otp(redis: Redis, phone_e164: str, purpose: str, code: str) -> None:
    """Raises OtpError on failure. Success deletes the OTP (single use)."""
    key = _key(purpose, hmac_hash(phone_e164))
    data = await redis.hgetall(key)
    if not data:
        raise OtpError("OTP expired or not requested. Please request a new one.")

    attempts = await redis.hincrby(key, "attempts", 1)
    if attempts > settings.OTP_MAX_ATTEMPTS:
        await redis.delete(key)
        raise OtpError("Too many wrong attempts. Please request a new OTP.", 429)

    if not constant_time_equals(data["code_hash"], sha256(code)):
        left = settings.OTP_MAX_ATTEMPTS - attempts
        if left <= 0:
            await redis.delete(key)
            raise OtpError("Incorrect OTP. Please request a new one.")
        raise OtpError(f"Incorrect OTP. {left} attempt(s) left.")

    await redis.delete(key)
