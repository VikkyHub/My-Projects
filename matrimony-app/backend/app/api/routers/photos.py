import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Request, Response, UploadFile, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import current_user
from app.core.config import settings
from app.db.session import get_db
from app.models import Photo, PrivacySettings, Profile, User
from app.schemas.social import PhotoOut, PhotoSettings
from app.services import images
from app.services.events import record_event
from app.services.profiles import compute_completeness, photo_count
from app.services.social import photo_keys
from app.services.storage import get_storage, verify_signature

router = APIRouter(tags=["photos"])
MEDIA_TYPES = {
    "webp": "image/webp",
    "webm": "audio/webm",
    "ogg": "audio/ogg",
    "m4a": "audio/mp4",
    "mp3": "audio/mpeg",
}


async def _me(db: AsyncSession, user: User) -> Profile:
    p = await db.scalar(select(Profile).where(Profile.user_id == user.id))
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Create your profile first")
    return p


def _out(p: Photo) -> PhotoOut:
    return PhotoOut(
        id=str(p.id),
        url=get_storage().signed_url(photo_keys(p.profile_id, p.id)["lg"]),
        status=p.status,
        is_primary=p.is_primary,
    )


async def _list(db: AsyncSession, profile_id) -> list[Photo]:
    return list(
        await db.scalars(
            select(Photo)
            .where(Photo.profile_id == profile_id, Photo.status != "rejected")
            .order_by(Photo.is_primary.desc(), Photo.sort, Photo.created_at)
        )
    )


async def _refresh_completeness(db: AsyncSession, profile: Profile) -> None:
    await db.refresh(profile)
    profile.completeness = compute_completeness(profile, await photo_count(db, profile.id))


@router.get("/profiles/me/photos", response_model=list[PhotoOut])
async def my_photos(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    me = await _me(db, user)
    return [_out(p) for p in await _list(db, me.id)]


@router.post("/profiles/me/photos", response_model=list[PhotoOut], status_code=201)
async def upload_photo(
    request: Request,
    file: UploadFile = File(...),
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    me = await _me(db, user)
    existing = await _list(db, me.id)
    if len(existing) >= settings.MAX_PHOTOS:
        raise HTTPException(422, f"You can upload up to {settings.MAX_PHOTOS} photos")

    data = await file.read(settings.MAX_PHOTO_BYTES + 1)
    if len(data) > settings.MAX_PHOTO_BYTES:
        raise HTTPException(413, "Photo must be under 10 MB")
    try:
        proc = images.process(data)
    except images.ImageError as e:
        raise HTTPException(422, str(e)) from None

    # Same photo (or near-identical) already on ANOTHER profile => likely stolen/fake.
    dup = await db.scalar(
        select(Photo.id).where(Photo.phash == proc.dhash, Photo.profile_id != me.id).limit(1)
    )
    photo = Photo(
        id=uuid.uuid4(),
        profile_id=me.id,
        phash=proc.dhash,
        is_primary=not any(p.is_primary for p in existing),
        sort=len(existing),
        status="approved" if settings.DEV_AUTO_APPROVE and not dup else "pending",
        reject_reason="duplicate_of_other_profile" if dup else None,
        storage_key="",
    )
    keys = photo_keys(me.id, photo.id)
    photo.storage_key = keys["lg"]
    st = get_storage()
    st.save(keys["lg"], proc.large)
    st.save(keys["sm"], proc.small)
    st.save(keys["blur"], proc.blur)
    db.add(photo)
    await db.flush()
    await _refresh_completeness(db, me)
    await db.commit()
    await record_event(
        "photo_duplicate" if dup else "photo_uploaded",
        category="photo",
        level="warning" if dup else "info",
        actor=me.public_id,
        actor_type="member",
        message="Same photo already used on another profile — held for review" if dup else None,
        request=request,
    )
    return [_out(p) for p in await _list(db, me.id)]


@router.delete("/profiles/me/photos/{photo_id}", response_model=list[PhotoOut])
async def delete_photo(
    photo_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await _me(db, user)
    photo = await db.get(Photo, photo_id)
    if photo is None or photo.profile_id != me.id:
        raise HTTPException(404, "Photo not found")
    was_primary = photo.is_primary
    for k in photo_keys(me.id, photo.id).values():
        get_storage().delete(k)
    await db.delete(photo)
    await db.flush()
    if was_primary:
        nxt = (await _list(db, me.id))[:1]
        if nxt:
            nxt[0].is_primary = True
    await _refresh_completeness(db, me)
    await db.commit()
    return [_out(p) for p in await _list(db, me.id)]


@router.post("/profiles/me/photos/{photo_id}/primary", response_model=list[PhotoOut])
async def make_primary(
    photo_id: uuid.UUID, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await _me(db, user)
    photo = await db.get(Photo, photo_id)
    if photo is None or photo.profile_id != me.id:
        raise HTTPException(404, "Photo not found")
    await db.execute(update(Photo).where(Photo.profile_id == me.id).values(is_primary=False))
    photo.is_primary = True
    await db.commit()
    return [_out(p) for p in await _list(db, me.id)]


@router.put("/profiles/me/photo-settings", response_model=PhotoSettings)
async def photo_settings(
    body: PhotoSettings, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await _me(db, user)
    priv = await db.get(PrivacySettings, me.id)
    if priv is None:
        priv = PrivacySettings(profile_id=me.id)
        db.add(priv)
    priv.photo_visibility = body.photo_visibility
    await db.commit()
    return body


@router.get("/profiles/me/photo-settings", response_model=PhotoSettings)
async def get_photo_settings(
    user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
):
    me = await _me(db, user)
    priv = await db.get(PrivacySettings, me.id)
    return PhotoSettings(photo_visibility=priv.photo_visibility if priv else "all")


@router.get("/media/{key:path}", include_in_schema=False)
async def media(key: str, exp: int, sig: str):
    """Serves stored files only with a valid, unexpired signature (dev local storage)."""
    if not verify_signature(key, exp, sig):
        raise HTTPException(403, "Link expired")
    data = get_storage().read(key)
    if data is None:
        raise HTTPException(404, "Not found")
    ext = key.rsplit(".", 1)[-1].lower()
    return Response(
        data,
        media_type=MEDIA_TYPES.get(ext, "application/octet-stream"),
        headers={"Cache-Control": "private, max-age=600", "X-Content-Type-Options": "nosniff"},
    )
