import asyncio

import structlog
import websockets
from websockets.server import WebSocketServerProtocol

from app.config import settings

logger = structlog.get_logger()


async def handle_connection(websocket: WebSocketServerProtocol) -> None:
    logger.info("client_connected", remote=str(websocket.remote_address))
    try:
        await websocket.wait_closed()
    finally:
        logger.info("client_disconnected", remote=str(websocket.remote_address))


async def start_ws_server() -> None:
    logger.info("ws_server_starting", port=settings.game_ws_port)
    async with websockets.serve(handle_connection, "0.0.0.0", settings.game_ws_port):
        logger.info("ws_server_started", port=settings.game_ws_port)
        await asyncio.get_running_loop().create_future()
