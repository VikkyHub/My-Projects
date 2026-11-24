from datetime import date

from tests.conftest import auth

PARENT = "+919811111111"
CANDIDATE = "+919822222222"


def payload(**overrides) -> dict:
    base = {
        "created_by": "self",
        "first_name": "priya",
        "last_name": "sharma",
        "gender": "female",
        "dob": "1997-05-14",
        "marital_status": "never_married",
        "height_cm": 162,
        "religion_id": 1,
        "community_id": 10,
        "sub_community_id": 100,
        "mother_tongue_id": 1,
        "accept_terms": True,
    }
    base.update(overrides)
    return base


async def test_create_self_profile(client, login):
    t = await login()
    r = await client.post("/profiles", json=payload(), headers=auth(t))
    assert r.status_code == 201, r.text
    p = r.json()
    assert p["public_id"].startswith("VM") and len(p["public_id"]) == 8
    assert p["first_name"] == "Priya"  # normalized
    assert p["status"] == "pending_review"  # self => consent implicit, awaits moderation
    assert p["candidate_consent_pending"] is False
    assert p["candidate_phone_masked"] == "+91******3210"
    assert p["privacy"]["photo_visibility"] == "all"
    assert p["completeness"] > 0
    assert "id" not in p and "user_id" not in p  # internal ids never exposed

    r = await client.get("/profiles/me", headers=auth(t))
    assert r.status_code == 200 and r.json()["public_id"] == p["public_id"]


async def test_one_profile_per_account(client, login):
    t = await login()
    assert (await client.post("/profiles", json=payload(), headers=auth(t))).status_code == 201
    assert (await client.post("/profiles", json=payload(), headers=auth(t))).status_code == 409


async def test_must_accept_terms(client, login):
    t = await login()
    r = await client.post("/profiles", json=payload(accept_terms=False), headers=auth(t))
    assert r.status_code == 422


async def test_minimum_age(client, login):
    t = await login()
    today = date.today()
    groom_20 = date(today.year - 20, 1, 1).isoformat()
    r = await client.post(
        "/profiles",
        json=payload(gender="male", dob=groom_20, first_name="Ravi"),
        headers=auth(t),
    )
    assert r.status_code == 422 and "21" in r.json()["detail"]


async def test_community_must_match_religion(client, login):
    t = await login()
    r = await client.post(
        "/profiles",
        json=payload(religion_id=2, community_id=10, sub_community_id=None),
        headers=auth(t),
    )
    assert r.status_code == 422 and "Community" in r.json()["detail"]


async def test_parent_created_profile_needs_candidate_otp(client, sms, login):
    t = await login(PARENT)
    r = await client.post(
        "/profiles",
        json=payload(created_by="parent", candidate_phone=CANDIDATE),
        headers=auth(t),
    )
    assert r.status_code == 201, r.text
    p = r.json()
    assert p["status"] == "draft"  # hidden until candidate consents
    assert p["candidate_consent_pending"] is True

    r = await client.post("/profiles/me/candidate-consent/send", headers=auth(t))
    assert r.status_code == 200
    code = sms.sent[CANDIDATE]  # OTP went to the CANDIDATE's phone

    r = await client.post(
        "/profiles/me/candidate-consent/verify", json={"code": code}, headers=auth(t)
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "pending_review"
    assert r.json()["candidate_consent_pending"] is False


async def test_parent_cannot_use_own_number_as_candidate(client, login):
    t = await login(PARENT)
    r = await client.post(
        "/profiles", json=payload(created_by="parent", candidate_phone=PARENT), headers=auth(t)
    )
    assert r.status_code == 422


async def test_duplicate_candidate_blocked(client, login):
    """Candidate made their own profile; a parent can't create a second one for them."""
    t_cand = await login(CANDIDATE)
    assert (await client.post("/profiles", json=payload(), headers=auth(t_cand))).status_code == 201
    t_parent = await login(PARENT)
    r = await client.post(
        "/profiles",
        json=payload(created_by="parent", candidate_phone=CANDIDATE),
        headers=auth(t_parent),
    )
    assert r.status_code == 409


async def test_update_profile_sections(client, login):
    t = await login()
    await client.post("/profiles", json=payload(), headers=auth(t))
    before = (await client.get("/profiles/me", headers=auth(t))).json()["completeness"]

    r = await client.patch(
        "/profiles/me",
        json={
            "diet": "veg",
            "about_me": "I am a software engineer who loves music, travel and cooking "
            "for family and friends.",
            "family": {
                "father_occupation": "Retired",
                "family_type": "nuclear",
                "brothers": 1,
                "brothers_married": 0,
            },
            "horoscope": {"rashi": "Mesha", "manglik": "no"},
        },
        headers=auth(t),
    )
    assert r.status_code == 200, r.text
    p = r.json()
    assert p["diet"] == "veg"
    assert p["family"]["family_type"] == "nuclear"
    assert p["horoscope"]["visible_to"] == "accepted"
    assert p["completeness"] > before


async def test_about_me_blocks_contact_details(client, login):
    t = await login()
    await client.post("/profiles", json=payload(), headers=auth(t))
    for text in (
        "call me 98765 43210",
        "mail me at a@b.com",
        "see www.example.com",
        "dowry expected",
    ):
        r = await client.patch("/profiles/me", json={"about_me": text}, headers=auth(t))
        assert r.status_code == 422, text


async def test_gender_and_dob_not_editable(client, login):
    t = await login()
    await client.post("/profiles", json=payload(), headers=auth(t))
    r = await client.patch("/profiles/me", json={"gender": "male"}, headers=auth(t))
    assert r.status_code == 422


async def test_changing_religion_clears_community(client, login):
    t = await login()
    await client.post("/profiles", json=payload(), headers=auth(t))
    r = await client.patch("/profiles/me", json={"religion_id": 2}, headers=auth(t))
    assert r.status_code == 200, r.text
    assert r.json()["community_id"] is None and r.json()["sub_community_id"] is None


async def test_master_data_cascade(client):
    rel = (await client.get("/master/religions")).json()
    assert {"id": 1, "name": "Hindu"} in rel
    comm = (await client.get("/master/communities", params={"religion_id": 1})).json()
    assert [c["name"] for c in comm] == ["Brahmin", "Reddy"]
    sub = (await client.get("/master/sub-communities", params={"community_id": 10})).json()
    assert sub == [{"id": 100, "name": "Iyer"}]


async def test_master_cities_education_occupations(client):
    assert (await client.get("/master/cities")).status_code == 200
    assert (await client.get("/master/education-levels")).status_code == 200
    assert (await client.get("/master/occupations")).status_code == 200
