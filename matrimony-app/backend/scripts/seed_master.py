"""Seed reference data. Idempotent: safe to run repeatedly.

    python -m scripts.seed_master

This is a STARTER list. Add/rename communities from the admin panel later (they are rows,
not code). Have someone from each community review the names before launch.
"""

import asyncio

from sqlalchemy import select

from app.db.session import SessionLocal, engine
from app.models import (
    City,
    Community,
    Country,
    EducationLevel,
    MotherTongue,
    Occupation,
    Plan,
    Religion,
    State,
    SubCommunity,
)

RELIGIONS: dict[str, dict[str, list[str]]] = {
    "Hindu": {
        "Brahmin": [
            "Iyer",
            "Iyengar",
            "Saraswat",
            "Deshastha",
            "Kokanastha",
            "Gaur",
            "Kanyakubj",
            "Niyogi",
            "Vaidiki",
            "Namboodiri",
            "Maithil",
        ],
        "Kshatriya": [],
        "Rajput": [],
        "Maratha": [],
        "Kayastha": [],
        "Agarwal": [],
        "Baniya": [],
        "Khatri": [],
        "Arora": [],
        "Jat": [],
        "Yadav": [],
        "Kurmi": [],
        "Reddy": [],
        "Kamma": [],
        "Kapu": [],
        "Velama": [],
        "Naidu": [],
        "Lingayat": [],
        "Vokkaliga": [],
        "Nair": [],
        "Ezhava": [],
        "Vanniyar": [],
        "Gounder": [],
        "Chettiar": [],
        "Mudaliar": [],
        "Nadar": [],
        "Thevar": [],
        "Patel": [],
        "Lohana": [],
        "Bhumihar": [],
        "Gupta": [],
        "Scheduled Caste": [],
        "Scheduled Tribe": [],
        "Other": [],
    },
    "Muslim": {"Sunni": [], "Shia": [], "Bohra": [], "Memon": [], "Khoja": [], "Other": []},
    "Christian": {
        "Roman Catholic": [],
        "Protestant": [],
        "Syrian Christian": [],
        "Pentecostal": [],
        "Orthodox": [],
        "Other": [],
    },
    "Sikh": {"Jat Sikh": [], "Khatri Sikh": [], "Ramgarhia": [], "Arora Sikh": [], "Other": []},
    "Jain": {"Digambar": [], "Shwetambar": [], "Other": []},
    "Buddhist": {"Navayana": [], "Other": []},
    "Parsi": {"Parsi": [], "Irani": []},
    "Jewish": {"Other": []},
    "No Religion": {},
    "Spiritual / Other": {},
}

MOTHER_TONGUES = [
    "Assamese",
    "Bengali",
    "Bhojpuri",
    "English",
    "Gujarati",
    "Hindi",
    "Kannada",
    "Kashmiri",
    "Konkani",
    "Malayalam",
    "Marathi",
    "Marwari",
    "Nepali",
    "Odia",
    "Punjabi",
    "Rajasthani",
    "Sindhi",
    "Tamil",
    "Telugu",
    "Tulu",
    "Urdu",
    "Other",
]

# Starter: major + Tier-2 cities. Load the full list from a CSV later.
INDIA: dict[str, list[tuple[str, int]]] = {
    "Andhra Pradesh": [("Visakhapatnam", 2), ("Vijayawada", 2), ("Guntur", 2), ("Tirupati", 3)],
    "Delhi": [("New Delhi", 1)],
    "Gujarat": [("Ahmedabad", 1), ("Surat", 2), ("Vadodara", 2), ("Rajkot", 2)],
    "Karnataka": [("Bengaluru", 1), ("Mysuru", 2), ("Hubballi", 2), ("Mangaluru", 2)],
    "Kerala": [("Kochi", 2), ("Thiruvananthapuram", 2), ("Kozhikode", 2)],
    "Madhya Pradesh": [("Indore", 2), ("Bhopal", 2)],
    "Maharashtra": [("Mumbai", 1), ("Pune", 1), ("Nagpur", 2), ("Nashik", 2), ("Aurangabad", 2)],
    "Punjab": [("Ludhiana", 2), ("Amritsar", 2), ("Jalandhar", 2)],
    "Rajasthan": [("Jaipur", 2), ("Jodhpur", 2), ("Udaipur", 3)],
    "Tamil Nadu": [("Chennai", 1), ("Coimbatore", 2), ("Madurai", 2), ("Tiruchirappalli", 2)],
    "Telangana": [("Hyderabad", 1), ("Warangal", 2)],
    "Uttar Pradesh": [("Lucknow", 2), ("Kanpur", 2), ("Noida", 2), ("Varanasi", 2), ("Agra", 2)],
    "West Bengal": [("Kolkata", 1), ("Siliguri", 3)],
    "Haryana": [("Gurugram", 1), ("Faridabad", 2)],
    "Bihar": [("Patna", 2)],
    "Odisha": [("Bhubaneswar", 2)],
    "Chandigarh": [("Chandigarh", 2)],
}

EDUCATION = [
    ("High School", 1),
    ("Diploma", 2),
    ("Bachelor's", 3),
    ("Bachelor's - Engineering", 3),
    ("Bachelor's - Medicine (MBBS)", 4),
    ("Master's", 4),
    ("MBA / PGDM", 4),
    ("CA / CS / ICWA", 4),
    ("Doctorate (PhD)", 5),
    ("Other", 0),
]

OCCUPATIONS = [
    ("Software Professional", "IT"),
    ("Hardware / Networking", "IT"),
    ("Doctor", "Medical"),
    ("Nurse", "Medical"),
    ("Pharmacist", "Medical"),
    ("Engineer (Non-IT)", "Engineering"),
    ("Teacher / Professor", "Education"),
    ("Chartered Accountant", "Finance"),
    ("Banking Professional", "Finance"),
    ("Lawyer", "Legal"),
    ("Civil Services (IAS/IPS/IFS)", "Government"),
    ("Government Employee", "Government"),
    ("Defence", "Government"),
    ("Business Owner", "Business"),
    ("Sales / Marketing", "Business"),
    ("Manager", "Business"),
    ("Architect", "Creative"),
    ("Designer", "Creative"),
    ("Not Working", "Other"),
    ("Other", "Other"),
]

# Placeholder prices (paise). Decide real pricing before launch.
PLANS = [
    # code, name, days, price_paise, credits, daily_interest_limit
    ("gold_3m", "Gold - 3 months", 90, 2_999_00, 40, 30),
    ("diamond_6m", "Diamond - 6 months", 180, 4_999_00, 100, 50),
    ("platinum_12m", "Platinum - 12 months", 365, 7_999_00, 250, 100),
]


async def get_or_create(db, model, defaults=None, **keys):
    obj = await db.scalar(select(model).filter_by(**keys))
    if obj is None:
        obj = model(**keys, **(defaults or {}))
        db.add(obj)
        await db.flush()
    elif defaults:
        for k, v in defaults.items():
            setattr(obj, k, v)
    return obj


async def main() -> None:
    async with SessionLocal() as db:
        for sort, (rname, comms) in enumerate(RELIGIONS.items()):
            r = await get_or_create(db, Religion, {"sort": sort}, name=rname)
            for cname, subs in comms.items():
                c = await get_or_create(db, Community, religion_id=r.id, name=cname)
                for sname in subs:
                    await get_or_create(db, SubCommunity, community_id=c.id, name=sname)

        for name in MOTHER_TONGUES:
            await get_or_create(db, MotherTongue, name=name)

        india = await get_or_create(db, Country, {"name": "India"}, iso2="IN")
        for sname, cities in INDIA.items():
            st = await get_or_create(db, State, country_id=india.id, name=sname)
            for cname, tier in cities:
                await get_or_create(db, City, {"tier": tier}, state_id=st.id, name=cname)

        for name, rank in EDUCATION:
            await get_or_create(db, EducationLevel, {"rank": rank}, name=name)
        for name, cat in OCCUPATIONS:
            await get_or_create(db, Occupation, {"category": cat}, name=name)
        for code, name, days, price, credits, limit in PLANS:
            await get_or_create(
                db,
                Plan,
                {
                    "name": name,
                    "duration_days": days,
                    "price_paise": price,
                    "contact_credits": credits,
                    "daily_interest_limit": limit,
                },
                code=code,
            )
        await db.commit()
    await engine.dispose()
    print("Master data seeded.")


if __name__ == "__main__":
    asyncio.run(main())
