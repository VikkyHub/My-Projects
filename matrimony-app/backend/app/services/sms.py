"""SMS providers. Swap via SMS_PROVIDER. Tests inject a fake through FastAPI dependency override."""

from typing import Protocol

import httpx
import structlog

from app.core.config import settings

log = structlog.get_logger()


class SmsProvider(Protocol):
    async def send_otp(self, phone_e164: str, code: str) -> None: ...


class ConsoleSms:
    """DEV ONLY: prints the OTP to the API log instead of sending it."""

    async def send_otp(self, phone_e164: str, code: str) -> None:
        log.warning("DEV OTP (not sent)", phone=phone_e164[-4:], code=code)


class Msg91Sms:
    """MSG91 Flow API. Needs a DLT-approved template with an ##otp## variable.

    Docs: https://docs.msg91.com  (verify the endpoint/payload against your account's docs)
    """

    URL = "https://control.msg91.com/api/v5/flow"

    def __init__(self, auth_key: str, template_id: str) -> None:
        if not auth_key or not template_id:
            raise RuntimeError("MSG91_AUTH_KEY and MSG91_OTP_TEMPLATE_ID are required")
        self.auth_key = auth_key
        self.template_id = template_id

    async def send_otp(self, phone_e164: str, code: str) -> None:
        payload = {
            "template_id": self.template_id,
            "short_url": "0",
            "recipients": [{"mobiles": phone_e164.lstrip("+"), "otp": code}],
        }
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(self.URL, json=payload, headers={"authkey": self.auth_key})
        if r.status_code >= 400:
            # never log the code or full number
            log.error("msg91 send failed", status=r.status_code, phone=phone_e164[-4:])
            raise RuntimeError("SMS provider error")


_provider: SmsProvider | None = None


def get_sms_provider() -> SmsProvider:
    global _provider
    if _provider is None:
        if settings.SMS_PROVIDER == "msg91":
            _provider = Msg91Sms(settings.MSG91_AUTH_KEY, settings.MSG91_OTP_TEMPLATE_ID)
        else:
            _provider = ConsoleSms()
    return _provider
