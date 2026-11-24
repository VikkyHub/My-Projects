import io

import pytest
from PIL import Image
from sqlalchemy import update

from app.db.session import SessionLocal
from app.models import Photo, Profile
from tests.conftest import auth


@pytest.fixture
def member(client, login):
    """Create an ACTIVE member; returns (tokens, public_id)."""
    n = {"i": 0}

    async def _make(gender="female", first="Priya", dob="1996-01-01", premium=False, **kw):
        n["i"] += 1
        phone = f"+9198{n['i']:08d}"
        t = await login(phone)
        body = {
            "created_by": "self",
            "first_name": first,
            "last_name": "Rao",
            "gender": gender,
            "dob": dob,
            "religion_id": 1,
            "community_id": 10,
            "mother_tongue_id": 1,
            "accept_terms": True,
            **kw,
        }
        r = await client.post("/profiles", json=body, headers=auth(t))
        assert r.status_code == 201, r.text
        pid = r.json()["public_id"]
        async with SessionLocal() as db:
            await db.execute(
                update(Profile)
                .where(Profile.public_id == pid)
                .values(status="active", is_premium=premium)
            )
            await db.commit()
        return t, pid

    return _make


def jpeg(w=600, h=800, color=(200, 80, 120)) -> bytes:
    img = Image.new("RGB", (w, h), color)
    for x in range(0, w, 40):  # some structure so the hash isn't trivial
        for y in range(h):
            img.putpixel((x, y), (x % 255, y % 255, 50))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    return buf.getvalue()


# ---------------- matches ----------------
async def test_matches_show_opposite_gender_only(client, member):
    a, _ = await member("female", "Priya")
    await member("male", "Rahul", dob="1993-01-01")
    await member("female", "Anita")
    r = await client.get("/matches", params={"mode": "all"}, headers=auth(a))
    assert r.status_code == 200, r.text
    names = [c["first_name"] for c in r.json()["items"]]
    assert names == ["Rahul"]
    card = r.json()["items"][0]
    assert card["name"] == "Rahul R."  # free viewer sees last-name initial
    assert "Same community" in card["match_reasons"]
    assert 0 <= card["match_score"] <= 100


async def test_recommended_is_two_way(client, member):
    a, _ = await member("female", "Priya", dob="1996-01-01")  # ~30
    b, _ = await member("male", "Rahul", dob="1993-01-01")
    # Rahul only wants brides aged 21-25 -> Priya doesn't fit his preferences
    await client.put(
        "/profiles/me/preferences", json={"age_min": 21, "age_max": 25}, headers=auth(b)
    )
    r = await client.get("/matches", headers=auth(a))
    assert r.json()["items"] == []
    r = await client.get("/matches", params={"mode": "all"}, headers=auth(a))
    assert len(r.json()["items"]) == 1  # still findable via plain search


async def test_preferences_validation(client, member):
    a, _ = await member()
    r = await client.put(
        "/profiles/me/preferences", json={"age_min": 30, "age_max": 25}, headers=auth(a)
    )
    assert r.status_code == 422
    r = await client.put(
        "/profiles/me/preferences",
        json={"age_min": 25, "age_max": 32, "community_ids": []},
        headers=auth(a),
    )
    assert r.status_code == 200 and r.json()["community_ids"] is None  # [] = any
    assert (await client.get("/profiles/me/preferences", headers=auth(a))).json()["age_max"] == 32


async def test_pagination_cursor(client, member):
    a, _ = await member("female")
    for i in range(14):
        await member("male", f"Groom{chr(65 + i)}", dob="1993-01-01")
    p1 = (await client.get("/matches", params={"mode": "all"}, headers=auth(a))).json()
    assert len(p1["items"]) == 12 and p1["next_cursor"]
    p2 = (
        await client.get(
            "/matches", params={"mode": "all", "cursor": p1["next_cursor"]}, headers=auth(a)
        )
    ).json()
    ids = {c["public_id"] for c in p1["items"]} | {c["public_id"] for c in p2["items"]}
    assert len(ids) == 14 and p2["next_cursor"] is None


# ---------------- interests + chat ----------------
async def test_interest_accept_opens_conversation_and_chat_needs_premium(client, member):
    a, _ = await member("female", "Priya")
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")

    r = await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))
    assert r.status_code == 201, r.text
    assert (
        await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))
    ).status_code == 409

    received = (await client.get("/interests", params={"box": "received"}, headers=auth(b))).json()
    assert len(received) == 1 and received[0]["profile"]["first_name"] == "Priya"
    counts = (await client.get("/interests/counts", headers=auth(b))).json()
    assert counts["received_pending"] == 1

    r = await client.post(f"/interests/{received[0]['id']}/accept", headers=auth(b))
    conv_id = r.json()["conversation_id"]

    convs = (await client.get("/conversations", headers=auth(a))).json()
    assert convs[0]["can_chat"] is False and convs[0]["blocked_reason"] == "premium_required"
    r = await client.post(
        f"/conversations/{conv_id}/messages", json={"body": "Hi"}, headers=auth(a)
    )
    assert r.status_code == 403

    # Make Rahul premium -> both can chat
    async with SessionLocal() as db:
        await db.execute(update(Profile).where(Profile.public_id == b_pid).values(is_premium=True))
        await db.commit()
    r = await client.post(
        f"/conversations/{conv_id}/messages", json={"body": "Hello Rahul!"}, headers=auth(a)
    )
    assert r.status_code == 201 and r.json()["flagged"] is False
    r = await client.post(
        f"/conversations/{conv_id}/messages",
        json={"body": "Please send money for customs"},
        headers=auth(a),
    )
    assert r.json()["flagged"] is True
    r = await client.post(
        f"/conversations/{conv_id}/messages", json={"body": "what about dowry"}, headers=auth(a)
    )
    assert r.status_code == 422

    assert (await client.get("/interests/counts", headers=auth(b))).json()["unread_messages"] == 2
    msgs = (await client.get(f"/conversations/{conv_id}/messages", headers=auth(b))).json()
    assert [m["body"] for m in msgs] == ["Hello Rahul!", "Please send money for customs"]
    await client.post(f"/conversations/{conv_id}/read", headers=auth(b))
    assert (await client.get("/interests/counts", headers=auth(b))).json()["unread_messages"] == 0
    # Accepted => full name visible
    assert (await client.get("/conversations", headers=auth(a))).json()[0]["profile"][
        "name"
    ] == "Rahul Rao"


async def test_reverse_pending_interest_conflict(client, member):
    a, a_pid = await member("female", "Priya")
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))
    r = await client.post("/interests", json={"public_id": a_pid}, headers=auth(b))
    assert r.status_code == 409 and "accept it" in r.json()["detail"]


async def test_daily_interest_limit(client, member):
    a, _ = await member("female")
    for i in range(6):
        _, pid = await member("male", f"Groom{chr(65 + i)}", dob="1993-01-01")
        r = await client.post("/interests", json={"public_id": pid}, headers=auth(a))
        assert r.status_code == (201 if i < 5 else 429), r.text


async def test_decline_and_withdraw(client, member):
    a, _ = await member("female")
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    c, c_pid = await member("male", "Kiran", dob="1993-01-01")
    i1 = (await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))).json()["id"]
    i2 = (await client.post("/interests", json={"public_id": c_pid}, headers=auth(a))).json()["id"]
    assert (await client.post(f"/interests/{i1}/decline", headers=auth(b))).status_code == 200
    assert (await client.post(f"/interests/{i2}/withdraw", headers=auth(a))).status_code == 200
    # Only the receiver can accept; already-resolved can't be re-accepted
    assert (await client.post(f"/interests/{i1}/accept", headers=auth(b))).status_code == 409
    assert (await client.post(f"/interests/{i2}/accept", headers=auth(a))).status_code == 404
    # Declined recently => can't resend
    r = await client.post("/interests", json={"public_id": b_pid}, headers=auth(a))
    assert r.status_code == 409


async def test_block_hides_everywhere(client, member):
    a, a_pid = await member("female")
    b, b_pid = await member("male", "Rahul", dob="1993-01-01")
    assert (await client.post(f"/profiles/{b_pid}/block", headers=auth(a))).status_code == 204
    assert (await client.get("/matches", params={"mode": "all"}, headers=auth(a))).json()[
        "items"
    ] == []
    assert (await client.get("/matches", params={"mode": "all"}, headers=auth(b))).json()[
        "items"
    ] == []
    assert (await client.get(f"/profiles/{a_pid}", headers=auth(b))).status_code == 404
    assert (
        await client.post("/interests", json={"public_id": a_pid}, headers=auth(b))
    ).status_code == 404


async def test_pending_review_member_cannot_send_interest(client, member, login):
    _, b_pid = await member("male", "Rahul", dob="1993-01-01")
    t = await login("+919777777777")
    await client.post(
        "/profiles",
        json={
            "created_by": "self",
            "first_name": "New",
            "gender": "female",
            "dob": "1997-01-01",
            "religion_id": 1,
            "accept_terms": True,
        },
        headers=auth(t),
    )
    r = await client.post("/interests", json={"public_id": b_pid}, headers=auth(t))
    assert r.status_code == 403 and "under review" in r.json()["detail"]


# ---------------- photos ----------------
async def test_photo_upload_privacy_and_signed_urls(client, member, tmp_path, monkeypatch):
    from app.services import storage

    monkeypatch.setattr(storage, "_storage", storage.LocalStorage(str(tmp_path)))
    a, a_pid = await member("female", "Priya")
    b, _ = await member("male", "Rahul", dob="1993-01-01")

    r = await client.post(
        "/profiles/me/photos", files={"file": ("me.jpg", jpeg(), "image/jpeg")}, headers=auth(a)
    )
    assert r.status_code == 201, r.text
    photos = r.json()
    assert len(photos) == 1 and photos[0]["is_primary"]
    url = photos[0]["url"]
    img = await client.get(url.removeprefix("/api/v1"))
    assert img.status_code == 200 and img.headers["content-type"] == "image/webp"
    assert "exif" not in Image.open(io.BytesIO(img.content)).info  # metadata stripped

    # tampered signature is refused
    assert (
        await client.get(url.removeprefix("/api/v1").replace("sig=", "sig=0"))
    ).status_code == 403

    assert photos[0]["status"] == "pending"
    # Pending photos are invisible to others
    card = (await client.get("/matches", params={"mode": "all"}, headers=auth(b))).json()["items"][
        0
    ]
    assert card["photo_url"] is None
    async with SessionLocal() as db:  # moderator approves
        await db.execute(update(Photo).values(status="approved"))
        await db.commit()

    # Set "only accepted" -> Rahul gets a blurred, locked photo
    await client.put(
        "/profiles/me/photo-settings", json={"photo_visibility": "accepted"}, headers=auth(a)
    )
    card = (await client.get("/matches", params={"mode": "all"}, headers=auth(b))).json()["items"][
        0
    ]
    assert card["photo_locked"] is True and "_blur" in card["photo_url"]
    await client.put(
        "/profiles/me/photo-settings", json={"photo_visibility": "all"}, headers=auth(a)
    )
    card = (await client.get("/matches", params={"mode": "all"}, headers=auth(b))).json()["items"][
        0
    ]
    assert card["photo_locked"] is False and "_sm" in card["photo_url"]

    # non-image rejected; limit enforced; delete works
    r = await client.post(
        "/profiles/me/photos",
        files={"file": ("x.jpg", b"not an image", "image/jpeg")},
        headers=auth(a),
    )
    assert r.status_code == 422
    r = await client.delete(f"/profiles/me/photos/{photos[0]['id']}", headers=auth(a))
    assert r.status_code == 200 and r.json() == []


async def test_public_profile_hides_horoscope_until_accepted(client, member):
    a, a_pid = await member("female", "Priya")
    b, _ = await member("male", "Rahul", dob="1993-01-01")
    await client.patch(
        "/profiles/me",
        json={
            "horoscope": {"rashi": "Mesha", "visible_to": "accepted"},
            "career": {"employer": "Secret Corp"},
        },
        headers=auth(a),
    )
    p = (await client.get(f"/profiles/{a_pid}", headers=auth(b))).json()
    assert p["horoscope"] is None and p["horoscope_locked"] is True
    assert "employer" not in (p["career"] or {})
