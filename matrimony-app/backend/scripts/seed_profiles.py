"""DEV ONLY: create sample members so Matches / Interests / Messages have people in them.

    python -m scripts.seed_profiles

- 30 brides: mobile 9000000001 … 9000000030
- 30 grooms: mobile 9000000031 … 9000000060
Log in as any of them with the dev OTP (123456). Every 3rd member is Premium (chat works).
Also approves any of YOUR profiles still waiting for review. Safe to run again.
"""

import asyncio
import random
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select, update

from app.core.config import settings
from app.core.security import encrypt, hmac_hash, new_public_id
from app.db.session import SessionLocal, engine
from app.models import (
    City,
    Community,
    Consent,
    EducationLevel,
    MotherTongue,
    Occupation,
    PartnerPreferences,
    PrivacySettings,
    Profile,
    ProfileCareer,
    ProfileFamily,
    ProfileHoroscope,
    Religion,
    User,
)
from app.services.profiles import compute_completeness

BRIDES = [
    "Aishwarya",
    "Ananya",
    "Bhavana",
    "Deepika",
    "Divya",
    "Gayathri",
    "Harini",
    "Ishita",
    "Kavya",
    "Lakshmi",
    "Meera",
    "Nandini",
    "Pooja",
    "Priyanka",
    "Radhika",
    "Sahana",
    "Sneha",
    "Swathi",
    "Tanvi",
    "Vaishnavi",
    "Aditi",
    "Shruti",
    "Keerthi",
    "Neha",
    "Ritika",
    "Sanjana",
    "Pallavi",
    "Madhuri",
    "Revathi",
    "Zoya",
]
GROOMS = [
    "Aditya",
    "Arjun",
    "Karthik",
    "Rahul",
    "Rohan",
    "Siddharth",
    "Vikram",
    "Varun",
    "Nikhil",
    "Pranav",
    "Harsha",
    "Manoj",
    "Sandeep",
    "Srinivas",
    "Vivek",
    "Abhishek",
    "Akash",
    "Gautam",
    "Kiran",
    "Mahesh",
    "Naveen",
    "Prakash",
    "Rajesh",
    "Sai",
    "Tarun",
    "Venkat",
    "Yash",
    "Anil",
    "Deepak",
    "Imran",
]
SURNAMES = [
    "Sharma",
    "Iyer",
    "Reddy",
    "Rao",
    "Nair",
    "Patel",
    "Kulkarni",
    "Deshpande",
    "Menon",
    "Gupta",
    "Agarwal",
    "Naidu",
    "Pillai",
    "Joshi",
    "Verma",
    "Chowdary",
    "Bhat",
    "Shetty",
]
ABOUT = [
    "Software engineer who loves Carnatic music, long drives and trying new recipes on weekends.",
    "Close to my family, fond of travel and reading. Looking for someone kind and grounded.",
    "Doctor by profession, foodie at heart. I value respect, humour and shared family values.",
    "I enjoy trekking, cricket and spending Sundays with family. Simple, cheerful and ambitious.",
    "Chartered accountant who paints in free time. Looking for a partner who is a best friend too.",
    "Teacher who believes in lifelong learning. Love classical dance, gardening and festivals.",
    "Working in a startup, I love building things. Weekends are for badminton and my nieces.",
    "Calm, family-oriented and spiritual. I enjoy temple visits, music and cooking for loved ones.",
]
FATHER = [
    "Retired bank manager",
    "Business owner",
    "Government officer",
    "Doctor",
    "Farmer",
    "Professor",
    "Engineer",
    "Retired army officer",
]
MOTHER = ["Homemaker", "Teacher", "Doctor", "Bank employee", "Business owner", "Retired professor"]
DIETS = ["veg", "veg", "non_veg", "eggetarian", "veg", "jain"]


async def main() -> None:
    if settings.ENV == "prod":
        raise SystemExit("Refusing to seed sample profiles in prod")
    rnd = random.Random(42)
    now = datetime.now(UTC)
    async with SessionLocal() as db:
        hindu = await db.scalar(select(Religion).where(Religion.name == "Hindu"))
        comms = (await db.scalars(select(Community).where(Community.religion_id == hindu.id))).all()
        comms = [c for c in comms if c.name not in ("Other", "Scheduled Caste", "Scheduled Tribe")]
        tongues = {t.name: t.id for t in await db.scalars(select(MotherTongue))}
        cities = (await db.scalars(select(City))).all()
        edus = (await db.scalars(select(EducationLevel).where(EducationLevel.rank >= 3))).all()
        occs = (await db.scalars(select(Occupation).where(Occupation.name != "Not Working"))).all()
        if not comms or not cities:
            raise SystemExit("Run `python -m scripts.seed_master` first")
        lang_cycle = ["Telugu", "Tamil", "Kannada", "Hindi", "Marathi", "Malayalam", "Gujarati"]

        created = 0
        for i in range(60):
            female = i < 30
            phone = f"+9190000000{i + 1:02d}"
            ph = hmac_hash(phone)
            if await db.scalar(select(User.id).where(User.phone_hash == ph)):
                continue
            user = User(phone_hash=ph, phone_enc=encrypt(phone), phone_verified_at=now)
            db.add(user)
            await db.flush()
            first = (BRIDES if female else GROOMS)[i % 30]
            age = rnd.randint(23, 31) if female else rnd.randint(25, 34)
            dob = date(date.today().year - age, rnd.randint(1, 12), rnd.randint(1, 28))
            p = Profile(
                user_id=user.id,
                public_id=new_public_id(),
                created_by=rnd.choice(["self", "self", "self", "parent", "sibling"]),
                candidate_phone_hash=ph,
                candidate_phone_enc=user.phone_enc,
                candidate_consent_at=now,
                first_name=first,
                last_name=rnd.choice(SURNAMES),
                gender="female" if female else "male",
                dob=dob,
                height_cm=rnd.randint(150, 170) if female else rnd.randint(165, 188),
                marital_status="never_married" if rnd.random() > 0.08 else "divorced",
                has_children=False,
                religion_id=hindu.id,
                community_id=rnd.choice(comms).id,
                mother_tongue_id=tongues.get(lang_cycle[i % len(lang_cycle)]),
                city_id=rnd.choice(cities).id,
                diet=rnd.choice(DIETS),
                smoke="no",
                drink=rnd.choice(["no", "no", "occasionally"]),
                about_me=rnd.choice(ABOUT),
                status="active",
                is_premium=(i % 3 == 0),
                last_active_at=now - timedelta(hours=rnd.randint(0, 240)),
            )
            p.privacy = PrivacySettings()
            p.family = ProfileFamily(
                father_occupation=rnd.choice(FATHER),
                mother_occupation=rnd.choice(MOTHER),
                brothers=rnd.randint(0, 2),
                brothers_married=0,
                sisters=rnd.randint(0, 2),
                sisters_married=0,
                family_type=rnd.choice(["nuclear", "joint"]),
                family_status=rnd.choice(["middle", "upper_middle", "rich"]),
                family_values=rnd.choice(["traditional", "moderate", "liberal"]),
            )
            p.career = ProfileCareer(
                education_level_id=rnd.choice(edus).id,
                occupation_id=rnd.choice(occs).id,
                employed_in=rnd.choice(["private", "private", "govt", "business"]),
                annual_income_band=rnd.randint(4, 10),
            )
            p.horoscope = (
                ProfileHoroscope(rashi="Mesha (Aries)", manglik="no", visible_to="accepted")
                if rnd.random() > 0.5
                else None
            )
            db.add(p)
            await db.flush()
            db.add(
                PartnerPreferences(
                    profile_id=p.id,
                    age_min=max(21, age - (6 if female else 8)),
                    age_max=age + (8 if female else 3),
                )
            )
            db.add_all(
                [
                    Consent(
                        user_id=user.id, purpose=k, version=settings.TERMS_VERSION, granted=True
                    )
                    for k in ("terms", "privacy", "candidate_consent")
                ]
            )
            p.completeness = compute_completeness(p, 0)
            created += 1

        # Approve your own test profiles too (no admin panel yet)
        res = await db.execute(
            update(Profile)
            .where(Profile.status == "pending_review", Profile.candidate_consent_at.is_not(None))
            .values(status="active")
        )
        await db.commit()
    await engine.dispose()
    print(f"Created {created} sample members. Approved {res.rowcount} pending profile(s).")
    print("Brides: 9000000001-9000000030 · Grooms: 9000000031-9000000060 · OTP 123456 (dev)")


if __name__ == "__main__":
    asyncio.run(main())
