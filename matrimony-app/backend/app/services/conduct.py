"""Conduct rules: block vulgar/abusive language and track violations.

Detection works on a normalised copy of the text so common disguises are caught:
  "F*CK", "f.u.c.k", "fuuuuck", "b1tch", "m@darchod", "c h u t i y a".
Words are matched as whole tokens or known stems, so innocent words that merely
*contain* a bad word ("class", "assessment", "Scunthorpe", "grandiose") are not blocked.

The offending text is never stored — only that a rule was broken (ConductViolation).
Lists are a starting point; extend them from the admin's review of reports.
"""

import re
import unicodedata
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import ConductViolation, User

# Whole words (after normalisation)
_WORDS = {
    # English
    "fuck",
    "fucker",
    "fucking",
    "fucked",
    "fck",
    "fuk",
    "fuq",
    "wtf",
    "stfu",
    "shit",
    "bullshit",
    "bitch",
    "bitches",
    "bastard",
    "asshole",
    "arsehole",
    "ass",
    "dick",
    "dickhead",
    "cock",
    "cunt",
    "pussy",
    "slut",
    "whore",
    "prick",
    "twat",
    "wanker",
    "motherfucker",
    "mf",
    "jackass",
    "dumbass",
    "boobs",
    "tits",
    "nude",
    "nudes",
    "sexy",
    "sex",
    "horny",
    "porn",
    "blowjob",
    "rape",
    # Hindi / Hinglish (romanised)
    "chutiya",
    "chutiye",
    "chutia",
    "chootiya",
    "madarchod",
    "maderchod",
    "mc",
    "behenchod",
    "bhenchod",
    "bhanchod",
    "bc",
    "bhosdi",
    "bhosdike",
    "bhosda",
    "bhosdiwale",
    "gaand",
    "gand",
    "gandu",
    "randi",
    "randwa",
    "harami",
    "haramzada",
    "haramkhor",
    "kutti",
    "kamina",
    "kamine",
    "lauda",
    "lavda",
    "lund",
    "loda",
    "lodu",
    "chod",
    "chodu",
    "jhaat",
    "jhatu",
    "tatti",
    "suar",
    # Telugu / Tamil / Kannada / Marathi / Bengali (romanised)
    "dengu",
    "denguta",
    "lanja",
    "lanjakodaka",
    "puku",
    "modda",
    "gudda",
    "erripuka",
    "otha",
    "ommala",
    "punda",
    "pundai",
    "thevidiya",
    "sunni",
    "koothi",
    "soole",
    "sule",
    "bolimaga",
    "tullu",
    "shaata",
    "zhavadya",
    "bokachoda",
    "khanki",
    "magi",
}

# Stems: a token STARTING with one of these is abusive (catches inflections/compounds)
_STEMS = (
    "fuck",
    "motherfuck",
    "bitch",
    "cunt",
    "asshol",
    "dickhead",
    "whore",
    "slut",
    "chutiy",
    "chootiy",
    "madarchod",
    "maderchod",
    "behenchod",
    "bhenchod",
    "bhosd",
    "gaandu",
    "haramzad",
    "randibaaz",
    "lanjako",
    "thevidiy",
)

# Native-script words (substring match after normalisation)
_NATIVE = (
    "चूतिया",
    "चुतिया",
    "मादरचोद",
    "बहनचोद",
    "भोसड़ी",
    "भोसडी",
    "रंडी",
    "गांडू",
    "हरामी",
    "लौड़ा",
    "लंड",
    "कुतिया",
    "देंगु",
    "లంజ",
    "దెంగు",
    "పూకు",
    "தேவடியா",
    "புண்ட",
    "ஓத்த",
    "ಸೂಳೆ",
    "ಬೋಳಿಮಗ",
)

_LEET = str.maketrans(
    {
        "@": "a",
        "4": "a",
        "0": "o",
        "1": "i",
        "!": "i",
        "3": "e",
        "$": "s",
        "5": "s",
        "7": "t",
        "+": "t",
        "|": "i",
    }
)
# f*ck / f**k / sh*t / b*tch with symbols in place of letters
_MASKED = [
    re.compile(p, re.I)
    for p in (
        r"\bf[\W_]*[u*@#][\W_]*[c*@#][\W_]*k",
        r"\bs[\W_]*h[\W_]*[i1!*][\W_]*t\b",
        r"\bb[\W_]*[i1!*][\W_]*t[\W_]*c[\W_]*h",
        r"\bc[\W_]*[u*][\W_]*n[\W_]*t\b",
    )
]
_SPACED = re.compile(r"\b(?:[a-z][\s.\-_*]){2,}[a-z]\b")


def _normalise(text: str) -> str:
    t = unicodedata.normalize("NFKC", text).lower().translate(_LEET)
    t = _SPACED.sub(lambda m: re.sub(r"[\s.\-_*]", "", m.group()), t)  # f.u.c.k -> fuck
    return re.sub(r"(.)\1{2,}", r"\1", t)  # fuuuuck -> fuck


@dataclass
class Verdict:
    ok: bool
    rule: str | None = None


def check_text(text: str | None) -> Verdict:
    if not text:
        return Verdict(True)
    if any(p.search(text) for p in _MASKED):
        return Verdict(False, "vulgar")
    t = _normalise(text)
    tokens = re.findall(r"[a-z]+", t)
    for tok in tokens:
        if tok in _WORDS or tok.startswith(_STEMS):
            return Verdict(False, "vulgar")
    if any(w in t for w in _NATIVE):
        return Verdict(False, "vulgar")
    return Verdict(True)


VULGAR_MESSAGE = (
    "Please keep conversations respectful — this message wasn't sent because it contains "
    "abusive or vulgar language."
)


async def record_violation(
    db: AsyncSession, user: User, context: str, rule: str
) -> datetime | None:
    """Store the violation; mute member chat after repeated ones. Returns mute end if muted now."""
    now = datetime.now(UTC)
    db.add(ConductViolation(user_id=user.id, context=context, rule=rule))
    await db.flush()
    recent = await db.scalar(
        select(func.count())
        .select_from(ConductViolation)
        .where(
            ConductViolation.user_id == user.id,
            ConductViolation.created_at >= now - timedelta(days=settings.CONDUCT_WINDOW_DAYS),
        )
    )
    muted = None
    if recent >= settings.CONDUCT_MUTE_AFTER and not (
        user.chat_muted_until and user.chat_muted_until > now
    ):
        muted = now + timedelta(hours=settings.CONDUCT_MUTE_HOURS)
        user.chat_muted_until = muted
    await db.commit()
    return muted
