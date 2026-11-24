"""Dropdown data for registration and profile editing."""

from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models import (
    City,
    Community,
    EducationLevel,
    MotherTongue,
    Occupation,
    Religion,
    State,
    SubCommunity,
)
from app.schemas.master import CityOption, EducationOption, Option

router = APIRouter(prefix="/master", tags=["master data"])

CACHE = "public, max-age=3600"


@router.get("/religions", response_model=list[Option])
async def religions(response: Response, db: AsyncSession = Depends(get_db)):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(
        select(Religion).where(Religion.active).order_by(Religion.sort, Religion.name)
    )
    return rows.all()


@router.get("/communities", response_model=list[Option])
async def communities(religion_id: int, response: Response, db: AsyncSession = Depends(get_db)):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(
        select(Community)
        .where(Community.religion_id == religion_id, Community.active)
        .order_by(Community.name)
    )
    return rows.all()


@router.get("/sub-communities", response_model=list[Option])
async def sub_communities(
    community_id: int, response: Response, db: AsyncSession = Depends(get_db)
):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(
        select(SubCommunity)
        .where(SubCommunity.community_id == community_id)
        .order_by(SubCommunity.name)
    )
    return rows.all()


@router.get("/mother-tongues", response_model=list[Option])
async def mother_tongues(response: Response, db: AsyncSession = Depends(get_db)):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(select(MotherTongue).order_by(MotherTongue.name))
    return rows.all()


@router.get("/cities", response_model=list[CityOption])
async def cities(response: Response, db: AsyncSession = Depends(get_db)):
    """All cities with their state, sorted by state then city (for a grouped dropdown)."""
    response.headers["Cache-Control"] = CACHE
    rows = await db.execute(
        select(City.id, City.name, State.name.label("state"))
        .join(State, State.id == City.state_id)
        .order_by(State.name, City.name)
    )
    return [CityOption(id=r.id, name=r.name, state=r.state) for r in rows]


@router.get("/education-levels", response_model=list[EducationOption])
async def education_levels(response: Response, db: AsyncSession = Depends(get_db)):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(
        select(EducationLevel).order_by(EducationLevel.rank.desc(), EducationLevel.name)
    )
    return rows.all()


@router.get("/occupations", response_model=list[Option])
async def occupations(response: Response, db: AsyncSession = Depends(get_db)):
    response.headers["Cache-Control"] = CACHE
    rows = await db.scalars(select(Occupation).order_by(Occupation.name))
    return rows.all()
