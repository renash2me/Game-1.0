import asyncio
import uuid

import structlog
import websockets
from websockets.server import WebSocketServerProtocol

from app.config import settings
from app.ws.manager import manager

logger = structlog.get_logger()


async def handle_connection(websocket: WebSocketServerProtocol) -> None:
    character_id: uuid.UUID | None = None
    try:
        character_id = await _authenticate(websocket)
        if character_id is None:
            return

        await manager.connect(character_id, websocket)
        await _on_map_join(character_id)

        async for raw in websocket:
            await _dispatch(character_id, raw)

    except websockets.exceptions.ConnectionClosedOK:
        pass
    except websockets.exceptions.ConnectionClosedError as e:
        logger.warning("ws_connection_error", error=str(e))
    finally:
        if character_id is not None:
            await _on_map_leave(character_id)
            await manager.disconnect(character_id)


async def _authenticate(websocket: WebSocketServerProtocol) -> uuid.UUID | None:
    from app.ws.handlers import handle_auth
    try:
        raw = await asyncio.wait_for(websocket.recv(), timeout=10.0)
        return await handle_auth(websocket, raw)
    except asyncio.TimeoutError:
        await websocket.close(4001, "Auth timeout")
        return None


async def _on_map_join(character_id: uuid.UUID) -> None:
    from app.ws.handlers import send_map_state
    await send_map_state(manager, character_id)


async def _on_map_leave(character_id: uuid.UUID) -> None:
    from app.redis_client import get_redis
    map_id = manager.get_map(character_id)
    if map_id:
        r = get_redis()
        await r.srem(f"online_players:{map_id}", str(character_id))


async def _dispatch(character_id: uuid.UUID, raw: str) -> None:
    from app.ws.handlers import dispatch
    await dispatch(manager, character_id, raw)


async def start_ws_server() -> None:
    logger.info("ws_server_starting", port=settings.game_ws_port)
    async with websockets.serve(handle_connection, "0.0.0.0", settings.game_ws_port):
        logger.info("ws_server_started", port=settings.game_ws_port)
        await asyncio.get_running_loop().create_future()
