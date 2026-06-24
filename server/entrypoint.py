import asyncio
import uvicorn
import structlog

from app.config import settings

logger = structlog.get_logger()


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


async def main() -> None:
    logger.info("aethermoor_starting", api_port=settings.game_api_port, ws_port=settings.game_ws_port)
    await asyncio.gather(start_api(), start_websocket())


if __name__ == "__main__":
    asyncio.run(main())
