"""Object storage for photos.

LocalStorage (dev) writes files under MEDIA_DIR and serves them through /media with
HMAC-signed, expiring URLs — the same contract an R2/S3 presigned URL gives in prod,
so switching backends later doesn't change any calling code.
"""

import hashlib
import hmac
import time
from pathlib import Path
from typing import Protocol
from urllib.parse import urlencode

from app.core.config import settings


class Storage(Protocol):
    def save(self, key: str, data: bytes) -> None: ...
    def delete(self, key: str) -> None: ...
    def read(self, key: str) -> bytes | None: ...
    def signed_url(self, key: str) -> str: ...


def _sign(key: str, exp: int) -> str:
    msg = f"{key}:{exp}".encode()
    return hmac.new(settings.JWT_SECRET.encode(), msg, hashlib.sha256).hexdigest()[:32]


def verify_signature(key: str, exp: int, sig: str) -> bool:
    return exp >= int(time.time()) and hmac.compare_digest(_sign(key, exp), sig)


class LocalStorage:
    def __init__(self, root: str) -> None:
        self.root = Path(root).resolve()

    def _path(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root not in p.parents:  # path traversal guard
            raise ValueError("bad key")
        return p

    def save(self, key: str, data: bytes) -> None:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)

    def read(self, key: str) -> bytes | None:
        p = self._path(key)
        return p.read_bytes() if p.is_file() else None

    def signed_url(self, key: str) -> str:
        # Round expiry to the TTL window so URLs are stable (browser-cacheable) for a while
        ttl = settings.PHOTO_URL_TTL_SECONDS
        exp = (int(time.time()) // ttl + 2) * ttl
        q = urlencode({"exp": exp, "sig": _sign(key, exp)})
        return f"{settings.API_PREFIX}/media/{key}?{q}"


_storage: Storage | None = None


def get_storage() -> Storage:
    global _storage
    if _storage is None:
        _storage = LocalStorage(settings.MEDIA_DIR)
    return _storage
