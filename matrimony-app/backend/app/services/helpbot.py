"""Help assistant: answers common questions instantly; hands over to the team otherwise.

Rule-based on purpose: answers are exact, consistent with how the app actually works,
cost nothing, and never invent policies. Each intent lists keywords (English + common
Hinglish); the best-scoring intent wins if it clears MIN_SCORE, otherwise the question
goes to the support team. To add a topic, add an Intent below.
"""

import re
from dataclasses import dataclass, field

MIN_SCORE = 2


@dataclass
class Intent:
    key: str
    title: str  # shown as a suggestion chip
    keywords: dict[str, int]  # word/phrase -> weight
    answer: str
    escalate: bool = False  # this topic always needs a person (e.g. payments, account deletion)
    suggest: list[str] = field(default_factory=list)


INTENTS: list[Intent] = [
    Intent(
        "otp",
        "Didn't get the OTP",
        {
            "otp": 3,
            "code": 2,
            "sms": 2,
            "verification code": 3,
            "not received": 2,
            "nahi aaya": 3,
            "not coming": 2,
            "didn't get": 2,
            "resend": 2,
            "login": 1,
        },
        "Sorry about that! A few things to try:\n"
        "• Wait 30 seconds, then tap **Resend OTP**.\n"
        "• Check the number is correct and has network signal; DND doesn't block OTPs.\n"
        "• You can request up to 3 OTPs an hour per number — if you hit the limit, try again in an hour.\n"
        "Still nothing? Tell me and I'll pass it to our team.",
        suggest=["login", "talk"],
    ),
    Intent(
        "login",
        "Can't log in",
        {
            "log in": 3,
            "login": 2,
            "sign in": 3,
            "logged out": 3,
            "cant login": 3,
            "account locked": 3,
            "suspended": 2,
            "banned": 2,
        },
        "You log in with your mobile number and a 6-digit OTP — there's no password.\n"
        "If it says your account is **suspended**, our safety team restricted it after a review; "
        "reply here and a team member will explain the next steps.",
        suggest=["otp", "talk"],
    ),
    Intent(
        "edit_profile",
        "Edit my profile",
        {
            "edit": 3,
            "change": 2,
            "update": 2,
            "profile": 1,
            "details": 1,
            "badalna": 3,
            "modify": 2,
        },
        "Go to **My Profile** and tap **Edit** on any section (basic details, about, career, family, horoscope). "
        "Changes save instantly.\n"
        "Your **date of birth and gender** can't be changed by you — ask here and our team will help after verification.",
        suggest=["photos", "review"],
    ),
    Intent(
        "dob_gender",
        "Wrong date of birth / gender",
        {"date of birth": 4, "dob": 4, "birthday": 2, "age wrong": 4, "gender": 3, "wrong age": 4},
        "Date of birth and gender are locked to prevent fake profiles. Please tell us the correct value — "
        "I'm passing this to our team, who may ask for an ID to confirm.",
        escalate=True,
    ),
    Intent(
        "photos",
        "Add or change photos",
        {
            "photo": 3,
            "photos": 3,
            "picture": 3,
            "pic": 2,
            "image": 2,
            "upload": 2,
            "dp": 2,
            "selfie": 2,
        },
        "On **My Profile → Photos**, tap **Add photo** (JPG, PNG or WEBP up to 10 MB, up to 6 photos). "
        "Tap ★ to make one your main photo.\n"
        "New photos are checked by our team before others see them — usually within a few hours. "
        "Use clear, recent photos of yourself only (no group photos or celebrities).",
        suggest=["photo_privacy", "review"],
    ),
    Intent(
        "photo_privacy",
        "Who can see my photos?",
        {
            "who can see": 4,
            "hide photo": 4,
            "photo privacy": 5,
            "blur": 3,
            "private": 2,
            "privacy": 2,
        },
        "You choose! On **My Profile → Photos → Visible to**:\n"
        "• **Everyone** — all members\n• **Premium members** — others see a blurred photo\n"
        "• **Only connections** — visible after you accept someone's interest.\n"
        "Location data is removed from every photo, and links to your photos expire after 10 minutes.",
        suggest=["photos", "safety"],
    ),
    Intent(
        "review",
        "Profile under review / needs changes",
        {
            "review": 3,
            "under review": 4,
            "pending": 3,
            "approved": 3,
            "approve": 3,
            "rejected": 3,
            "needs changes": 4,
            "not visible": 3,
            "not showing": 3,
        },
        "Every new profile is checked by our team to keep the community genuine — usually within 24 hours.\n"
        "If it says **Needs changes**, the note on your profile page tells you what to fix. "
        "Save your changes and it goes back for review automatically.",
        suggest=["edit_profile", "talk"],
    ),
    Intent(
        "consent",
        "Profile created by a parent",
        {
            "parent": 3,
            "father": 2,
            "mother": 2,
            "son": 2,
            "daughter": 2,
            "consent": 4,
            "brother": 2,
            "sister": 2,
            "on behalf": 3,
            "for my son": 4,
            "for my daughter": 4,
        },
        "If you created the profile for someone else, it stays hidden until **they confirm with an OTP on "
        "their own phone** — this protects people from being listed without their knowledge.\n"
        "Open **My Profile** and tap **Send OTP to …**, then enter the code they receive.",
    ),
    Intent(
        "matches",
        "How do matches work?",
        {
            "match": 3,
            "matches": 3,
            "recommended": 3,
            "no matches": 4,
            "search": 2,
            "preference": 3,
            "preferences": 3,
            "rishta": 3,
        },
        "**Recommended** shows people who fit your partner preferences *and* whose preferences fit you, "
        "ranked by a match %. Tap **Partner preferences** to widen them, or use **Search all** to see everyone "
        "with your own filters.",
        suggest=["interests", "edit_profile"],
    ),
    Intent(
        "interests",
        "Sending interests",
        {
            "interest": 3,
            "interests": 3,
            "send interest": 4,
            "limit": 2,
            "accept": 2,
            "decline": 2,
            "withdraw": 2,
        },
        "Tap **Send interest** on a profile. If they accept, you're connected.\n"
        "Free members can send **5 interests a day** (Premium: 50). You can withdraw a pending one from "
        "**Interests → Sent**. If someone declines, you can't send them another for 30 days.",
        suggest=["chat", "premium"],
    ),
    Intent(
        "chat",
        "Why can't I message someone?",
        {
            "message": 2,
            "chat": 3,
            "can't message": 4,
            "cannot chat": 4,
            "msg": 2,
            "talk to match": 3,
            "baat": 2,
        },
        "Chat opens when an **interest is accepted**, and **one of you has Premium**.\n"
        "If chat is closed, the other person may have blocked the conversation. "
        "If you've been restricted for language, the message shows when you can chat again.",
        suggest=["premium", "safety"],
    ),
    Intent(
        "premium",
        "Premium plans & payments",
        {
            "premium": 4,
            "plan": 3,
            "plans": 3,
            "price": 3,
            "payment": 4,
            "pay": 2,
            "refund": 4,
            "subscription": 4,
            "upgrade": 3,
            "money deducted": 5,
            "paisa": 2,
        },
        "Premium unlocks chat, more interests a day and full names. Plans are launching soon.\n"
        "For anything about a **payment or refund**, I'm connecting you with our team so a person can check it.",
        escalate=True,
    ),
    Intent(
        "verification",
        "Verification badges",
        {
            "verify": 3,
            "verified": 3,
            "verification": 3,
            "aadhaar": 4,
            "aadhar": 4,
            "badge": 3,
            "id proof": 4,
            "pan": 2,
        },
        "Your **mobile number** is verified when you log in. ID verification (Aadhaar via DigiLocker, PAN, "
        "driving licence or passport) is optional and coming soon — we never store your full Aadhaar number.",
    ),
    Intent(
        "safety",
        "Stay safe / scams",
        {
            "scam": 5,
            "fraud": 5,
            "money": 2,
            "asking money": 5,
            "fake": 3,
            "cheat": 4,
            "unsafe": 4,
            "harass": 5,
            "harassment": 5,
            "threat": 5,
            "blackmail": 5,
            "dowry": 5,
        },
        "Your safety comes first:\n• **Never send money** or share OTPs, bank or card details.\n"
        "• Meet in a public place and tell family where you'll be.\n"
        "• On their profile, tap **⋯ → Report** or **Block** — blocking hides you from each other instantly.\n"
        "If someone is threatening or blackmailing you, tell me — I'll alert our safety team right away.",
        suggest=["block", "talk"],
    ),
    Intent(
        "block",
        "Block or report someone",
        {"block": 4, "report": 4, "unblock": 3, "stop messaging": 4, "disturbing": 3},
        "Open their profile and tap **⋯** → **Block** (you'll disappear from each other everywhere and chat "
        "closes) or **Report** (our team reviews it). You can also report from inside a chat with the 🚩 button.",
        suggest=["safety"],
    ),
    Intent(
        "delete",
        "Delete my account",
        {
            "delete": 4,
            "remove account": 5,
            "deactivate": 4,
            "close account": 5,
            "delete profile": 5,
            "hide profile": 3,
            "my data": 3,
        },
        "I'm sorry to see you go. Account deletion and data export are handled by our team for now — "
        "I'm passing your request on, and a team member will confirm before anything is deleted.",
        escalate=True,
    ),
    Intent(
        "language",
        "Language & translation",
        {
            "language": 4,
            "translate": 5,
            "hindi": 3,
            "tamil": 3,
            "telugu": 3,
            "kannada": 3,
            "marathi": 3,
            "bhasha": 3,
        },
        "Tap **Translate** under any message to read it in your language — choose it with the 🌐 selector "
        "at the top of the chat. Translation runs in your browser, so your messages stay private.",
    ),
    Intent(
        "talk",
        "Talk to a person",
        {
            "human": 5,
            "person": 4,
            "agent": 5,
            "team": 3,
            "customer care": 5,
            "support": 3,
            "call me": 5,
            "talk to": 3,
            "representative": 5,
            "executive": 4,
        },
        "Sure — I'm connecting you with our support team. They usually reply within a few hours.",
        escalate=True,
    ),
]

GREETING = re.compile(
    r"^\s*(hi+|hello+|hey+|namaste|namaskar|vanakkam|good (morning|evening|afternoon))\b", re.I
)
THANKS = re.compile(r"\b(thanks|thank you|thx|dhanyavad|shukriya|ok thanks|got it|solved)\b", re.I)

WELCOME = (
    "Hi! I'm the Matrimony help assistant. Ask me anything about your profile, photos, matches, "
    "interests, chat or safety — or tap a topic below. If I can't help, I'll connect you with our team."
)
HANDOVER = (
    "I'm not sure I have the right answer for that, so I've passed your question to our support team. "
    "A team member will reply here — usually within a few hours. You can add details, a screenshot or a "
    "voice note meanwhile."
)

BY_KEY = {i.key: i for i in INTENTS}


@dataclass
class BotReply:
    text: str
    intent: str | None
    escalate: bool
    suggestions: list[dict]
    ask_feedback: bool


def _score(intent: Intent, text: str, words: set[str]) -> int:
    s = 0
    for kw, w in intent.keywords.items():
        if (" " in kw and kw in text) or kw in words:
            s += w
    return s


def chips(keys: list[str]) -> list[dict]:
    return [{"key": k, "title": BY_KEY[k].title} for k in keys if k in BY_KEY]


DEFAULT_CHIPS = ["otp", "photos", "review", "matches", "chat", "safety", "talk"]


def answer(text: str, intent_key: str | None = None) -> BotReply:
    """intent_key: when the member tapped a suggestion chip."""
    if intent_key and intent_key in BY_KEY:
        it = BY_KEY[intent_key]
        return BotReply(it.answer, it.key, it.escalate, chips(it.suggest), not it.escalate)
    t = text.lower().strip()
    if THANKS.search(t) and len(t) < 40:
        return BotReply(
            "You're welcome! Anything else I can help with?", "thanks", False, [], False
        )
    if GREETING.match(t) and len(t.split()) <= 3:
        return BotReply(WELCOME, "greeting", False, chips(DEFAULT_CHIPS), False)
    words = set(re.findall(r"[a-z']+", t))
    best, best_score = None, 0
    for it in INTENTS:
        sc = _score(it, t, words)
        if sc > best_score:
            best, best_score = it, sc
    if best is None or best_score < MIN_SCORE:
        return BotReply(HANDOVER, None, True, [], False)
    return BotReply(best.answer, best.key, best.escalate, chips(best.suggest), not best.escalate)
