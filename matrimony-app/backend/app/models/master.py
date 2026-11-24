"""Reference data editable from the admin panel (not enums -> no deploy to add a community)."""

from sqlalchemy import Boolean, ForeignKey, SmallInteger, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Religion(Base):
    __tablename__ = "religions"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80), unique=True)
    sort: Mapped[int] = mapped_column(SmallInteger, default=0)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Community(Base):
    __tablename__ = "communities"
    __table_args__ = (UniqueConstraint("religion_id", "name", name="uq_community_religion_name"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    religion_id: Mapped[int] = mapped_column(ForeignKey("religions.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class SubCommunity(Base):
    __tablename__ = "sub_communities"
    __table_args__ = (UniqueConstraint("community_id", "name", name="uq_subcommunity_comm_name"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    community_id: Mapped[int] = mapped_column(ForeignKey("communities.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))


class MotherTongue(Base):
    __tablename__ = "mother_tongues"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(60), unique=True)


class Country(Base):
    __tablename__ = "countries"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    iso2: Mapped[str] = mapped_column(String(2), unique=True)


class State(Base):
    __tablename__ = "states"
    id: Mapped[int] = mapped_column(primary_key=True)
    country_id: Mapped[int] = mapped_column(ForeignKey("countries.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))


class City(Base):
    __tablename__ = "cities"
    id: Mapped[int] = mapped_column(primary_key=True)
    state_id: Mapped[int] = mapped_column(ForeignKey("states.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    tier: Mapped[int | None] = mapped_column(SmallInteger)


class EducationLevel(Base):
    __tablename__ = "education_levels"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    rank: Mapped[int] = mapped_column(SmallInteger)  # for ">= graduate" filters


class Occupation(Base):
    __tablename__ = "occupations"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    category: Mapped[str | None] = mapped_column(String(60))
