from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.api.routers import auth, chat, interests, master, matches, photos, profiles
from app.core.config import settings
from app.core.redis import close_redis, get_redis
from app.db.session import SessionLocal, engine


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await close_redis()
    await engine.dispose()


app = FastAPI(
    title=f"{settings.APP_NAME} API",
    version="0.1.0",
    lifespan=lifespan,
    # Don't publish interactive docs in production
    docs_url=None if settings.ENV == "prod" else "/docs",
    redoc_url=None,
    openapi_url=None if settings.ENV == "prod" else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    if settings.ENV == "prod":
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
    return response


for r in (
    auth.router,
    master.router,
    profiles.router,  # before matches: /profiles/me must win over /profiles/{public_id}
    photos.router,
    matches.router,
    interests.router,
    chat.router,
):
    app.include_router(r, prefix=settings.API_PREFIX)


@app.get("/health", tags=["ops"])
async def health():
    async with SessionLocal() as s:
        await s.execute(text("SELECT 1"))
    await get_redis().ping()
    return {"status": "ok"}
