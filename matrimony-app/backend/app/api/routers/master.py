"""Dropdown data for registration: religion -> community -> sub-community, mother tongue."""

from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models import Community, MotherTongue, Religion, SubCommunity
from app.schemas.master import Option

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
