"""Tokens, hashing and field-level encryption.

- Phone numbers / emails are stored twice: an HMAC hash (for lookups / uniqueness)
  and an AES-GCM ciphertext (for display). A leaked DB dump exposes neither.
- Refresh tokens are opaque random strings; only their SHA-256 is stored.
"""

import base64
import hashlib
import hmac
import os
import secrets
import time
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import settings

try:
    _ENC_KEY = base64.urlsafe_b64decode(settings.DATA_ENC_KEY)
except ValueError:
    _ENC_KEY = b""
if len(_ENC_KEY) != 32:
    raise RuntimeError(
        "DATA_ENC_KEY in .env is not a valid key. For local dev, delete that line from .env. "
        'For prod, generate one with: python -c "import os,base64; '
        'print(base64.urlsafe_b64encode(os.urandom(32)).decode())"'
    )
_aes = AESGCM(_ENC_KEY)


# ---------- deterministic hashing (lookups) ----------
def hmac_hash(value: str) -> str:
    return hmac.new(settings.PHONE_HASH_KEY.encode(), value.encode(), hashlib.sha256).hexdigest()


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


# ---------- reversible encryption (display) ----------
def encrypt(plaintext: str) -> bytes:
    nonce = os.urandom(12)
    return nonce + _aes.encrypt(nonce, plaintext.encode(), None)


def decrypt(blob: bytes) -> str:
    return _aes.decrypt(blob[:12], blob[12:], None).decode()


def mask_phone(e164: str) -> str:
    """+919876543210 -> +91******3210"""
    return e164[:3] + "*" * (len(e164) - 7) + e164[-4:]


# ---------- OTP ----------
def generate_otp(length: int) -> str:
    return "".join(secrets.choice("0123456789") for _ in range(length))


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())


# ---------- JWT access tokens ----------
def create_access_token(user_id: uuid.UUID, role: str, scope: str = "member") -> tuple[str, int]:
    expires_in = settings.ACCESS_TOKEN_MINUTES * 60
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "role": role,
        "scope": scope,  # "admin" only for tokens from the staff login (password + TOTP)
        "type": "access",
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM), expires_in


def decode_access_token(token: str) -> dict:
    payload = jwt.decode(
        token,
        settings.JWT_SECRET,
        algorithms=[settings.JWT_ALGORITHM],
        options={"require": ["sub", "exp", "type"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload


# ---------- refresh tokens ----------
def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


# ---------- public profile ids ----------
_PUBLIC_ID_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # no 0/O/1/I


def new_public_id() -> str:
    return "VM" + "".join(secrets.choice(_PUBLIC_ID_ALPHABET) for _ in range(6))


# ---------- staff passwords (scrypt, stdlib) ----------
def hash_password(password: str) -> str:
    salt = os.urandom(16)
    n, r, p = 2**15, 8, 1
    dk = hashlib.scrypt(password.encode(), salt=salt, n=n, r=r, p=p, maxmem=64 * 1024 * 1024)
    return f"scrypt${n}${r}${p}${base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}"


def verify_password(password: str, stored: str | None) -> bool:
    if not stored:
        # still spend the time so "unknown email" isn't faster than "wrong password"
        hashlib.scrypt(b"x", salt=b"0" * 16, n=2**15, r=8, p=1, maxmem=64 * 1024 * 1024)
        return False
    try:
        _, n, r, p, salt, dk = stored.split("$")
        calc = hashlib.scrypt(
            password.encode(),
            salt=base64.b64decode(salt),
            n=int(n),
            r=int(r),
            p=int(p),
            maxmem=64 * 1024 * 1024,
        )
    except ValueError:
        return False
    return hmac.compare_digest(calc, base64.b64decode(dk))


# ---------- TOTP (RFC 6238, works with Google/Microsoft Authenticator) ----------
def new_totp_secret() -> str:
    return base64.b32encode(os.urandom(20)).decode().rstrip("=")


def _hotp(secret_b32: str, counter: int) -> str:
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8))
    digest = hmac.new(key, counter.to_bytes(8, "big"), hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    code = (int.from_bytes(digest[off : off + 4], "big") & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


def totp_now(secret_b32: str, at: float | None = None) -> str:
    return _hotp(secret_b32, int((at if at is not None else time.time()) // 30))


def verify_totp(secret_b32: str, code: str, window: int = 1) -> bool:
    """Accept the current 30s step and ±1 step for clock drift."""
    step = int(time.time() // 30)
    return any(
        hmac.compare_digest(_hotp(secret_b32, step + d), code) for d in range(-window, window + 1)
    )


def totp_uri(secret_b32: str, email: str, issuer: str) -> str:
    from urllib.parse import quote

    label = quote(f"{issuer}:{email}")
    return f"otpauth://totp/{label}?secret={secret_b32}&issuer={quote(issuer)}&digits=6&period=30"
