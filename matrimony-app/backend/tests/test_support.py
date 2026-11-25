import io

from PIL import Image
from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models import AppEvent, ConductViolation
from tests.conftest import auth
from tests.test_admin import staff_login  # noqa: F401  (fixture)
from tests.test_social import jpeg, member  # noqa: F401  (fixture)

WEBM = b"\x1a\x45\xdf\xa3" + b"\x00" * 2000  # EBML header = WebM/Opus voice note


async def say(client, t, text=None, intent=None):
    r = await client.post(
        "/support/messages", json={"body": text or "", "intent": intent}, headers=auth(t)
    )
    assert r.status_code == 200, r.text
    return r.json()


async def test_bot_answers_known_question_without_team(client, login):
    t = await login()  # no profile needed for help
    v = await say(client, t, "I didn't get the OTP")
    assert v["ticket"]["status"] == "bot"
    assert [m["sender"] for m in v["messages"]] == ["member", "bot"]
    bot = v["messages"][-1]
    assert (
        "Resend OTP" in bot["body"]
        and bot["meta"]["intent"] == "otp"
        and bot["meta"]["ask_feedback"]
    )


async def test_suggestion_chip_answer(client, login):
    t = await login()
    v = await say(client, t, intent="photo_privacy")
    assert v["messages"][0]["body"] == "Who can see my photos?"
    assert "Visible to" in v["messages"][1]["body"]


async def test_unknown_question_goes_to_team_then_staff_replies(client, login, staff_login):  # noqa: F811
    t = await login()
    v = await say(client, t, "My horoscope pdf export is cut off on the second page")
    assert v["ticket"]["status"] == "waiting_team"
    async with SessionLocal() as db:
        assert (
            await db.scalar(
                select(func.count())
                .select_from(AppEvent)
                .where(AppEvent.event == "support_escalated")
            )
            == 1
        )

    s = await staff_login()
    inbox = (await client.get("/admin/support", headers=auth(s))).json()
    assert len(inbox) == 1 and inbox[0]["unread"] == 1
    tid = inbox[0]["id"]
    d = (
        await client.post(
            f"/admin/support/{tid}/reply",
            json={"body": "We'll fix the PDF today."},
            headers=auth(s),
        )
    ).json()
    assert d["ticket"]["status"] == "answered"

    v = (await client.get("/support", headers=auth(t))).json()
    assert v["messages"][-1]["sender"] == "staff" and v["messages"][-1]["staff_name"]
    # once a person is handling it, the bot stays quiet and the team is notified
    v = await say(client, t, "thanks, also how do I add photos?")
    assert v["ticket"]["status"] == "waiting_team" and v["messages"][-1]["sender"] == "member"


async def test_not_helpful_escalates(client, login):
    t = await login()
    v = await say(client, t, "how do matches work")
    bot_id = v["messages"][-1]["id"]
    v = (
        await client.post(
            "/support/feedback", json={"message_id": bot_id, "helpful": False}, headers=auth(t)
        )
    ).json()
    assert v["ticket"]["status"] == "waiting_team"


async def test_payments_and_urgent_go_straight_to_team(client, login, staff_login):  # noqa: F811
    t = await login()
    assert (await say(client, t, "money deducted but premium not active"))["ticket"][
        "status"
    ] == "waiting_team"
    t2 = await login("+919811111111")
    v = await say(client, t2, "a man I met here is threatening to leak my photos")
    assert v["ticket"]["status"] == "waiting_team" and "112" in v["messages"][-1]["body"]
    s = await staff_login()
    rows = {
        r["subject"][:10]: r for r in (await client.get("/admin/support", headers=auth(s))).json()
    }
    assert any(r["urgent"] for r in rows.values())


async def test_attachments_photo_and_voice(client, login, tmp_path, monkeypatch):
    from app.services import storage

    monkeypatch.setattr(storage, "_storage", storage.LocalStorage(str(tmp_path)))
    t = await login()
    r = await client.post(
        "/support/attachments",
        data={"kind": "voice", "duration_s": "7"},
        files={"file": ("v.webm", WEBM, "audio/webm")},
        headers=auth(t),
    )
    assert r.status_code == 200, r.text
    voice = [m for m in r.json()["messages"] if m["kind"] == "voice"][0]
    assert voice["duration_s"] == 7 and r.json()["ticket"]["status"] == "waiting_team"
    audio = await client.get(voice["media_url"].removeprefix("/api/v1"))
    assert audio.status_code == 200 and audio.headers["content-type"] == "audio/webm"

    bad = await client.post(
        "/support/attachments",
        data={"kind": "voice"},
        files={"file": ("v.webm", b"<script>alert(1)</script>", "audio/webm")},
        headers=auth(t),
    )
    assert bad.status_code == 422

    img = Image.new("RGB", (800, 600), (10, 120, 200))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    r = await client.post(
        "/support/attachments",
        data={"kind": "photo"},
        files={"file": ("s.jpg", buf.getvalue(), "image/jpeg")},
        headers=auth(t),
    )
    photo = [m for m in r.json()["messages"] if m["kind"] == "photo"][0]
    got = await client.get(photo["media_url"].removeprefix("/api/v1"))
    assert got.headers["content-type"] == "image/webp"


async def test_vulgar_blocked_in_help_chat(client, login):
    t = await login()
    r = await client.post(
        "/support/messages", json={"body": "this app is f*cking useless"}, headers=auth(t)
    )
    assert r.status_code == 422 and "respectful" in r.json()["detail"]
    async with SessionLocal() as db:
        assert await db.scalar(select(func.count()).select_from(ConductViolation)) == 1


async def test_member_chat_vulgar_then_mute(client, member):  # noqa: F811
    a, _ = await member("female", "Priya", premium=True)
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    iid = (await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))).json()["id"]
    conv = (await client.post(f"/interests/{iid}/accept", headers=auth(b))).json()[
        "conversation_id"
    ]
    url = f"/conversations/{conv}/messages"
    assert (
        await client.post(url, json={"body": "hello, nice to meet you"}, headers=auth(b))
    ).status_code == 201
    for _ in range(2):
        r = await client.post(url, json={"body": "you are a chutiya"}, headers=auth(b))
        assert r.status_code == 422
    r = await client.post(url, json={"body": "b1tch"}, headers=auth(b))
    assert r.status_code == 403 and "24 hours" in r.json()["detail"]
    # now even polite messages are refused until the mute ends
    r = await client.post(url, json={"body": "sorry"}, headers=auth(b))
    assert r.status_code == 403 and "until" in r.json()["detail"]
    # the other side can still chat
    assert (await client.post(url, json={"body": "ok"}, headers=auth(a))).status_code == 201
    # and the muted member can still reach the help desk
    assert (
        await client.post("/support/messages", json={"body": "why am I muted"}, headers=auth(b))
    ).status_code == 200
    async with SessionLocal() as db:
        ev = {e.event for e in await db.scalars(select(AppEvent))}
    assert {"vulgar_language_blocked", "member_muted"} <= ev


async def test_vulgar_about_me_and_interest_note(client, member):  # noqa: F811
    a, _ = await member("female", "Priya")
    _, b_pid = await member("male", "Rahul", dob="1993-01-01")
    r = await client.patch(
        "/profiles/me", json={"about_me": "No time wasters, no bullshit please"}, headers=auth(a)
    )
    assert r.status_code == 422
    r = await client.post(
        "/interests", json={"public_id": b_pid, "note": "hey sexy"}, headers=auth(a)
    )
    assert r.status_code == 422
    async with SessionLocal() as db:
        assert await db.scalar(select(func.count()).select_from(ConductViolation)) == 2


async def test_inbox_is_staff_only_and_translate_unconfigured(client, login):
    t = await login()
    assert (await client.get("/admin/support", headers=auth(t))).status_code == 401
    r = await client.post("/translate", json={"text": "नमस्ते", "target": "en"}, headers=auth(t))
    assert r.status_code == 503
