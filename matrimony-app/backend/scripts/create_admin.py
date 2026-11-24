"""Create the first admin (or any staff) account from the command line.

    python -m scripts.create_admin --email you@example.com --name "Your Name"

You'll be asked for a password (min 10 chars, letters + numbers). Then open
http://localhost:5173/admin/login, sign in, and scan the QR code with Google
Authenticator / Microsoft Authenticator to finish setting up two-step login.
Further staff should be invited from the admin panel (Staff page), not this script.
"""

import argparse
import asyncio
import getpass

from sqlalchemy import select

from app.core.security import encrypt, hash_password, hmac_hash
from app.db.session import SessionLocal, engine
from app.models import User
from app.schemas.admin import _strong


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--role", choices=["admin", "moderator"], default="admin")
    ap.add_argument(
        "--password", help="(avoid: ends up in shell history) prompt is used if omitted"
    )
    a = ap.parse_args()
    email = a.email.strip().lower()

    pw = a.password
    while not pw:
        p1 = getpass.getpass("Password (min 10 chars, letters + numbers): ")
        try:
            _strong(p1)
        except ValueError as e:
            print(f"  {e}")
            continue
        if getpass.getpass("Repeat password: ") != p1:
            print("  Passwords don't match")
            continue
        pw = p1
    _strong(pw)

    async with SessionLocal() as db:
        if await db.scalar(select(User.id).where(User.email_hash == hmac_hash(email))):
            raise SystemExit(f"An account with {email} already exists")
        db.add(
            User(
                email_hash=hmac_hash(email),
                email_enc=encrypt(email),
                name=a.name.strip(),
                role=a.role,
                password_hash=hash_password(pw),
            )
        )
        await db.commit()
    await engine.dispose()
    print(f"Created {a.role} {email}.")
    print("Next: open http://localhost:5173/admin/login and set up your authenticator app.")


if __name__ == "__main__":
    asyncio.run(main())
