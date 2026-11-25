"""Import every model so Base.metadata is complete (Alembic autogenerate, tests)."""

from app.models.billing import ContactUnlock, Payment, Plan, Subscription
from app.models.event import AppEvent
from app.models.interaction import (
    Block,
    Conversation,
    DailyMatch,
    Interest,
    Message,
    ProfileView,
    Report,
    Shortlist,
)
from app.models.master import (
    City,
    Community,
    Country,
    EducationLevel,
    MotherTongue,
    Occupation,
    Religion,
    State,
    SubCommunity,
)
from app.models.profile import (
    PartnerPreferences,
    Photo,
    PrivacySettings,
    Profile,
    ProfileCareer,
    ProfileFamily,
    ProfileHoroscope,
    Verification,
)
from app.models.user import AdminAction, Consent, Device, RefreshToken, User

__all__ = [
    "AdminAction",
    "AppEvent",
    "Block",
    "City",
    "Community",
    "Consent",
    "ContactUnlock",
    "Conversation",
    "Country",
    "DailyMatch",
    "Device",
    "EducationLevel",
    "Interest",
    "Message",
    "MotherTongue",
    "Occupation",
    "PartnerPreferences",
    "Payment",
    "Photo",
    "Plan",
    "PrivacySettings",
    "Profile",
    "ProfileCareer",
    "ProfileFamily",
    "ProfileHoroscope",
    "ProfileView",
    "RefreshToken",
    "Religion",
    "Report",
    "Shortlist",
    "State",
    "SubCommunity",
    "Subscription",
    "User",
    "Verification",
]
