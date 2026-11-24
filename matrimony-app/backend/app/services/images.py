"""Photo processing: validate, strip metadata (EXIF/GPS), resize, WebP, blur, dHash."""

import io
from dataclasses import dataclass

from PIL import Image, ImageFilter, ImageOps, UnidentifiedImageError

Image.MAX_IMAGE_PIXELS = 40_000_000  # decompression-bomb guard
ALLOWED = {"JPEG", "PNG", "WEBP"}


class ImageError(ValueError):
    pass


@dataclass
class Processed:
    large: bytes  # max 1080px
    small: bytes  # 400px thumbnail
    blur: bytes  # heavily blurred, for viewers not allowed to see the photo
    dhash: int


def _webp(img: Image.Image, max_side: int, quality: int = 82) -> bytes:
    im = img.copy()
    im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=quality, method=4)  # new file => no EXIF/GPS carried over
    return buf.getvalue()


def dhash(img: Image.Image) -> int:
    """64-bit difference hash; near-identical photos have a small Hamming distance."""
    g = img.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
    px = list(g.tobytes())  # one byte per pixel in mode L
    bits = 0
    for row in range(8):
        for col in range(8):
            bits = (bits << 1) | (px[row * 9 + col] > px[row * 9 + col + 1])
    return bits - (1 << 63)  # store as signed BIGINT


def process(data: bytes) -> Processed:
    try:
        probe = Image.open(io.BytesIO(data))
        fmt = probe.format
        probe.verify()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as e:
        raise ImageError("That file isn't a valid image") from e
    if fmt not in ALLOWED:
        raise ImageError("Please upload a JPG, PNG or WEBP photo")

    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img)  # respect phone rotation, then drop EXIF
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    w, h = img.size
    if min(w, h) < 300:
        raise ImageError("Photo is too small — please use one at least 300×300 pixels")

    blur_src = img.copy()
    blur_src.thumbnail((240, 240))
    blurred = blur_src.filter(ImageFilter.GaussianBlur(18))
    return Processed(
        large=_webp(img, 1080),
        small=_webp(img, 400, quality=78),
        blur=_webp(blurred, 240, quality=60),
        dhash=dhash(img),
    )
