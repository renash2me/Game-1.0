import asyncio
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.auth import router as auth_router
from app.api.characters import router as characters_router
from app.api.inventory import router as inventory_router
from app.api.quests import router as quests_router
from app.data.loader import load_all

logger = structlog.get_logger()

_ai_tasks: list[asyncio.Task] = []


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_all()
    logger.info("static_catalogs_loaded")

    from app.systems.mob_spawn import initialize_all_maps
    await initialize_all_maps()

    yield

    for task in _ai_tasks:
        task.cancel()
    if _ai_tasks:
        await asyncio.gather(*_ai_tasks, return_exceptions=True)


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
app.include_router(inventory_router)
app.include_router(quests_router)


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "aethermoor-api"}
