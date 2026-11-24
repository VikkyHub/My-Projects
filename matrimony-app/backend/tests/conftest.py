"""Tests run against a real Postgres + Redis (same as prod), not SQLite/mocks.

Defaults: database `matrimony_test` and Redis DB 15. Override with TEST_DATABASE_URL /
TEST_REDIS_URL. With docker compose running: `pytest` just works.
"""

import os

os.environ["ENV"] = "test"
os.environ["DATABASE_URL"] = os.getenv(
    "TEST_DATABASE_URL", "postgresql+asyncpg://matri:matri@localhost:55432/matrimony_test"
)
os.environ["OTP_MAX_SENDS_PER_IP_PER_HOUR"] = "10000"  # tests log in many members
os.environ["REDIS_URL"] = os.getenv("TEST_REDIS_URL", "redis://localhost:6379/15")

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

import app.models  # noqa: E402,F401
from app.core.redis import get_redis  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Community, MotherTongue, Religion, SubCommunity  # noqa: E402
from app.services.sms import get_sms_provider  # noqa: E402


class FakeSms:
    def __init__(self) -> None:
        self.sent: dict[str, str] = {}

    async def send_otp(self, phone_e164: str, code: str) -> None:
        self.sent[phone_e164] = code


@pytest.fixture(scope="session", autouse=True)
async def _schema():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as db:
        hindu = Religion(id=1, name="Hindu")
        muslim = Religion(id=2, name="Muslim")
        db.add_all([hindu, muslim])
        await db.flush()
        db.add_all(
            [
                Community(id=10, religion_id=1, name="Brahmin"),
                Community(id=11, religion_id=1, name="Reddy"),
                Community(id=20, religion_id=2, name="Sunni"),
            ]
        )
        await db.flush()
        db.add_all(
            [SubCommunity(id=100, community_id=10, name="Iyer"), MotherTongue(id=1, name="Telugu")]
        )
        await db.commit()
    yield
    await engine.dispose()


@pytest.fixture(autouse=True)
async def _clean():
    yield
    async with engine.begin() as conn:
        await conn.execute(
            text(
                "TRUNCATE users, admin_actions, consents, refresh_tokens, profiles, photos, "
                "interests, "
                "conversations, messages, blocks, shortlists, reports, profile_views CASCADE"
            )
        )
    await get_redis().flushdb()


@pytest.fixture
def sms() -> FakeSms:
    fake = FakeSms()
    app.dependency_overrides[get_sms_provider] = lambda: fake
    yield fake
    app.dependency_overrides.pop(get_sms_provider, None)


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test/api/v1") as c:
        yield c


@pytest.fixture
def login(client, sms):
    """Returns an async fn: phone -> login response json."""

    async def _login(phone: str = "+919876543210") -> dict:
        redis = get_redis()
        async for k in redis.scan_iter("otp:cooldown:*"):  # tests log in repeatedly
            await redis.delete(k)
        r = await client.post("/auth/otp/send", json={"phone": phone})
        assert r.status_code == 200, r.text
        r = await client.post("/auth/otp/verify", json={"phone": phone, "code": sms.sent[phone]})
        assert r.status_code == 200, r.text
        return r.json()

    return _login


def auth(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}
