from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.auth import router as auth_router
from app.api.characters import router as characters_router
from app.data.loader import load_all

logger = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_all()
    logger.info("static_catalogs_loaded")
    yield


app = FastAPI(
    title="Aethermoor Game API",
    version="0.1.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(characters_router)


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "aethermoor-api"}
