"""DEV ONLY: put some work in the admin queues so you can try the panel.

    python -m scripts.seed_moderation

- 4 new profiles waiting for review (mobiles 9000000061-9000000064), with photos
- 2 photos waiting for review on existing sample members
- 3 open reports (incl. one about a money request in chat)
Run seed_master and seed_profiles first. Safe to run again (skips what exists).
"""

import asyncio
import io
import uuid
from datetime import UTC, date, datetime

from PIL import Image, ImageDraw
from sqlalchemy import select

from app.core.config import settings
from app.core.security import encrypt, hmac_hash, new_public_id
from app.db.session import SessionLocal, engine
from app.models import (
    City,
    Community,
    Conversation,
    Interest,
    Message,
    Photo,
    PrivacySettings,
    Profile,
    Religion,
    Report,
    User,
)
from app.services import images
from app.services.social import photo_keys
from app.services.storage import get_storage

PENDING = [
    ("Meghana", "Kulkarni", "female", (214, 110, 140)),
    ("Ritu", "Verma", "female", (120, 150, 210)),
    ("Anand", "Pillai", "male", (90, 160, 140)),
    ("Suresh", "Gupta", "male", (200, 150, 80)),
]


def portrait(color: tuple[int, int, int]) -> bytes:
    img = Image.new("RGB", (720, 900), (250, 240, 235))
    d = ImageDraw.Draw(img)
    for y in range(900):
        d.line([(0, y), (720, y)], fill=tuple(int(c * (0.6 + y / 2250)) for c in color))
    d.ellipse([230, 170, 490, 430], fill=(236, 196, 164))
    d.rounded_rectangle([170, 470, 550, 900], radius=120, fill=(60, 30, 50))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return buf.getvalue()


async def add_photo(db, profile: Profile, color, primary: bool) -> None:
    proc = images.process(portrait(color))
    ph = Photo(
        id=uuid.uuid4(),
        profile_id=profile.id,
        phash=proc.dhash,
        is_primary=primary,
        status="pending",
        storage_key="",
    )
    keys = photo_keys(profile.id, ph.id)
    ph.storage_key = keys["lg"]
    st = get_storage()
    st.save(keys["lg"], proc.large)
    st.save(keys["sm"], proc.small)
    st.save(keys["blur"], proc.blur)
    db.add(ph)


async def main() -> None:
    if settings.ENV == "prod":
        raise SystemExit("Refusing to seed in prod")
    now = datetime.now(UTC)
    async with SessionLocal() as db:
        hindu = await db.scalar(select(Religion).where(Religion.name == "Hindu"))
        comm = await db.scalar(select(Community).where(Community.religion_id == hindu.id))
        city = await db.scalar(select(City))
        made = 0
        for i, (first, last, gender, color) in enumerate(PENDING):
            phone = f"+9190000000{61 + i}"
            if await db.scalar(select(User.id).where(User.phone_hash == hmac_hash(phone))):
                continue
            u = User(phone_hash=hmac_hash(phone), phone_enc=encrypt(phone), phone_verified_at=now)
            db.add(u)
            await db.flush()
            p = Profile(
                user_id=u.id,
                public_id=new_public_id(),
                created_by="self",
                candidate_phone_hash=u.phone_hash,
                candidate_phone_enc=u.phone_enc,
                candidate_consent_at=now,
                first_name=first,
                last_name=last,
                gender=gender,
                dob=date(1995 + i, 3, 10),
                height_cm=160 + i * 5,
                marital_status="never_married",
                religion_id=hindu.id,
                community_id=comm.id,
                city_id=city.id,
                about_me="New here! Looking for a kind, family-oriented partner.",
                status="pending_review",
                completeness=55,
                last_active_at=now,
            )
            p.privacy = PrivacySettings()
            db.add(p)
            await db.flush()
            await add_photo(db, p, color, primary=True)
            made += 1

        members = (
            await db.scalars(
                select(Profile)
                .where(Profile.status == "active")
                .order_by(Profile.public_id)
                .limit(5)
            )
        ).all()
        if len(members) >= 5 and not await db.scalar(select(Report.id).limit(1)):
            for m, color in zip(members[:2], [(180, 90, 160), (90, 120, 200)], strict=True):
                await add_photo(db, m, color, primary=False)
            a, b, c, d, e = members[:5]
            db.add(
                Report(
                    reporter_id=a.id,
                    reported_id=b.id,
                    reason="fake",
                    details="Photos look like a model from Instagram.",
                )
            )
            db.add(
                Report(
                    reporter_id=c.id,
                    reported_id=b.id,
                    reason="fake",
                    details="Same photos as another site.",
                )
            )
            # a chat with a money request, then reported
            i = Interest(sender_id=d.id, receiver_id=e.id, status="accepted", responded_at=now)
            db.add(i)
            await db.flush()
            conv = Conversation(
                interest_id=i.id, profile_a=d.id, profile_b=e.id, last_message_at=now
            )
            db.add(conv)
            await db.flush()
            msg = Message(
                conversation_id=conv.id,
                sender_id=e.id,
                flagged=True,
                body="My father is in hospital, please send ₹20,000 by UPI, I'll return it.",
            )
            db.add(msg)
            await db.flush()
            db.add(
                Report(
                    reporter_id=d.id,
                    reported_id=e.id,
                    reason="scam_money",
                    details="Asked for money in the second message.",
                    message_id=msg.id,
                )
            )

        await db.commit()
    await engine.dispose()
    print(f"Added {made} profiles to the review queue, plus sample photos and reports.")


if __name__ == "__main__":
    asyncio.run(main())
