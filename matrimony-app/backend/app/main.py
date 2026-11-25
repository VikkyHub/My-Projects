import asyncio
import secrets
import time
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.api.routers import (
    admin,
    admin_auth,
    auth,
    chat,
    interests,
    master,
    matches,
    photos,
    profiles,
    support,
)
from app.core.config import settings
from app.core.redis import close_redis, get_redis
from app.db.session import SessionLocal, engine
from app.services.events import purge_loop, record_event


@asynccontextmanager
async def lifespan(_: FastAPI):
    purge = None
    if settings.ENV != "test":
        purge = asyncio.create_task(purge_loop())
        await record_event(
            "app_started", category="system", message=f"API started ({settings.ENV})"
        )
    yield
    if purge:
        purge.cancel()
        with suppress(asyncio.CancelledError):
            await purge
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
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
)


@app.middleware("http")
async def request_context(request: Request, call_next):
    """Request ID on every request/response; server errors go to the application log."""
    rid = request.headers.get("x-request-id", "")[:32] or secrets.token_hex(8)
    request.state.request_id = rid
    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception as e:
        await record_event(
            "server_error",
            category="system",
            level="error",
            request=request,
            message=f"{request.method} {request.url.path} — {type(e).__name__}",
            meta={"error": str(e)[:300]},
        )
        raise
    if response.status_code >= 500:
        await record_event(
            "server_error",
            category="system",
            level="error",
            request=request,
            message=f"{request.method} {request.url.path} returned {response.status_code}",
        )
    response.headers["X-Request-ID"] = rid
    response.headers["Server-Timing"] = f"app;dur={(time.perf_counter() - start) * 1000:.0f}"
    return response


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
    admin_auth.router,
    admin.router,
    support.router,
):
    app.include_router(r, prefix=settings.API_PREFIX)


@app.get("/health", tags=["ops"])
async def health():
    async with SessionLocal() as s:
        await s.execute(text("SELECT 1"))
    await get_redis().ping()
    return {"status": "ok"}
