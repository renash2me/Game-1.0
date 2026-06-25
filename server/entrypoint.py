import asyncio
import subprocess
import uvicorn
import structlog

from app.config import settings

logger = structlog.get_logger()


def run_migrations() -> None:
    logger.info("running_migrations")
    result = subprocess.run(["alembic", "upgrade", "head"], capture_output=True, text=True)
    if result.returncode != 0:
        logger.error("migration_failed", stderr=result.stderr)
        raise RuntimeError(f"Alembic migration failed:\n{result.stderr}")
    logger.info("migrations_ok", output=result.stdout.strip())


async def start_api() -> None:
    config = uvicorn.Config(
        "app.main:app",
        host="0.0.0.0",
        port=settings.game_api_port,
        log_level="info",
        loop="asyncio",
    )
    server = uvicorn.Server(config)
    await server.serve()


async def start_websocket() -> None:
    from app.ws.server import start_ws_server
    await start_ws_server()


async def start_checkpoint() -> None:
    from app.systems.checkpoint import periodic_checkpoint
    await periodic_checkpoint()


async def main() -> None:
    logger.info("aethermoor_starting", api_port=settings.game_api_port, ws_port=settings.game_ws_port)
    run_migrations()
    await asyncio.gather(start_api(), start_websocket(), start_checkpoint())


if __name__ == "__main__":
    asyncio.run(main())
