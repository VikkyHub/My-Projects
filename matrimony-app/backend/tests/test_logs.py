from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.db.session import SessionLocal
from app.main import app
from app.models import AppEvent
from app.services.events import purge_old_events
from tests.conftest import auth
from tests.test_admin import PW, make_staff, staff_login  # noqa: F401  (fixture)
from tests.test_social import member  # noqa: F401  (fixture)


async def events(**filters) -> list[AppEvent]:
    async with SessionLocal() as db:
        q = select(AppEvent).order_by(AppEvent.id)
        for k, v in filters.items():
            q = q.where(getattr(AppEvent, k) == v)
        return list((await db.scalars(q)).all())


async def test_member_login_events_and_no_full_phone(client, sms):
    phone = "+919876543210"
    await client.post("/auth/otp/send", json={"phone": phone})
    await client.post(
        "/auth/otp/verify",
        json={"phone": phone, "code": "000000" if sms.sent[phone] != "000000" else "111111"},
    )
    await client.post("/auth/otp/verify", json={"phone": phone, "code": sms.sent[phone]})
    names = [e.event for e in await events(category="auth")]
    assert names == ["otp_sent", "otp_failed", "member_signup"]
    for e in await events():
        blob = f"{e.actor} {e.message} {e.meta}"
        assert "9876543210" not in blob  # only masked numbers are logged
    failed = (await events(event="otp_failed"))[0]
    assert failed.level == "warning" and failed.actor == "+91******3210" and failed.request_id


async def test_staff_failed_login_and_lockout_logged(client):
    await make_staff()
    for _ in range(5):
        await client.post(
            "/admin/auth/login", json={"email": "mod@example.com", "password": "nope"}
        )
    assert len(await events(event="staff_login_failed")) == 5
    locked = await events(event="staff_locked_out")
    assert len(locked) == 1 and locked[0].level == "error"
    await client.post("/admin/auth/login", json={"email": "ghost@example.com", "password": "x"})
    ghost = (await events(event="staff_login_failed"))[-1]
    assert ghost.actor_type == "anonymous" and ghost.message == "Unknown email"


async def test_flagged_message_logged_without_text(client, member):  # noqa: F811
    a, _ = await member("female", "Priya", premium=True)
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    iid = (await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))).json()["id"]
    conv = (await client.post(f"/interests/{iid}/accept", headers=auth(b))).json()[
        "conversation_id"
    ]
    await client.post(
        f"/conversations/{conv}/messages", json={"body": "send money via UPI pls"}, headers=auth(a)
    )
    flagged = await events(event="message_flagged")
    assert len(flagged) == 1
    assert "UPI" not in f"{flagged[0].message} {flagged[0].meta}"
    assert {"interest_sent", "interest_accepted"} <= {
        e.event for e in await events(category="interest")
    }


async def test_admin_reads_logs_moderator_cannot(client, staff_login, sms):  # noqa: F811
    await client.post("/auth/otp/send", json={"phone": "+919811111111"})
    mod = await staff_login("mod@example.com", "moderator")
    assert (await client.get("/admin/logs", headers=auth(mod))).status_code == 403
    adm = await staff_login("boss@example.com", "admin")
    page = (await client.get("/admin/logs", headers=auth(adm))).json()
    got = [i["event"] for i in page["items"]]
    assert "otp_sent" in got and {"staff_login", "staff_2fa_setup"} & set(got)
    staff_only = (
        await client.get("/admin/logs", params={"category": "staff"}, headers=auth(adm))
    ).json()
    assert {i["category"] for i in staff_only["items"]} == {"staff"}
    mine = (
        await client.get("/admin/logs", params={"actor": "boss@example.com"}, headers=auth(adm))
    ).json()
    assert mine["items"] and all(i["actor"] == "boss@example.com" for i in mine["items"])
    summary = (await client.get("/admin/logs/summary", headers=auth(adm))).json()
    assert summary["events_24h"] >= 3 and summary["staff_logins_24h"] == 2


async def test_log_pagination(client, staff_login):  # noqa: F811
    adm = await staff_login("boss@example.com", "admin")
    async with SessionLocal() as db:
        db.add_all([AppEvent(level="info", category="system", event=f"e{i}") for i in range(7)])
        await db.commit()
    p1 = (await client.get("/admin/logs", params={"limit": 5}, headers=auth(adm))).json()
    assert len(p1["items"]) == 5 and p1["next_before_id"]
    p2 = (
        await client.get(
            "/admin/logs", params={"limit": 5, "before_id": p1["next_before_id"]}, headers=auth(adm)
        )
    ).json()
    assert not ({i["id"] for i in p1["items"]} & {i["id"] for i in p2["items"]})


async def test_server_error_is_logged(client):
    async def boom():
        raise RuntimeError("database exploded")

    app.add_api_route("/api/v1/__boom", boom)
    try:
        with pytest.raises(RuntimeError):
            await client.get("/__boom")
    finally:
        app.router.routes = [
            r for r in app.router.routes if getattr(r, "path", "") != "/api/v1/__boom"
        ]
    err = await events(event="server_error")
    assert len(err) == 1 and err[0].level == "error" and "RuntimeError" in err[0].message


async def test_request_id_header(client):
    r = await client.get("/master/religions")
    assert len(r.headers["x-request-id"]) == 16
    r = await client.get("/master/religions", headers={"X-Request-ID": "trace-abc"})
    assert r.headers["x-request-id"] == "trace-abc"


async def test_retention_purge():
    async with SessionLocal() as db:
        db.add(
            AppEvent(
                level="info",
                category="system",
                event="old",
                created_at=datetime.now(UTC) - timedelta(days=91),
            )
        )
        db.add(AppEvent(level="info", category="system", event="new"))
        await db.commit()
    assert await purge_old_events() == 1
    assert [e.event for e in await events()] == ["new"]
