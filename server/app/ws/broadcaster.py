import asyncio
import json
import uuid

import structlog
from websockets.exceptions import ConnectionClosed

from app.ws.connection_manager import ConnectionManager

logger = structlog.get_logger()


async def _send(manager: ConnectionManager, character_id: uuid.UUID, message: dict) -> None:
    ws = manager.get_socket(character_id)
    if ws is None:
        return
    try:
        await ws.send(json.dumps(message))
    except ConnectionClosed:
        pass


async def send_to(manager: ConnectionManager, character_id: uuid.UUID, message: dict) -> None:
    await _send(manager, character_id, message)


async def broadcast_map(
    manager: ConnectionManager,
    map_id: str,
    message: dict,
    exclude: uuid.UUID | None = None,
) -> None:
    members = manager.get_map_members(map_id)
    targets = [cid for cid in members if cid != exclude]
    if not targets:
        return
    payload = json.dumps(message)
    await asyncio.gather(
        *(_send_raw(manager, cid, payload) for cid in targets),
        return_exceptions=True,
    )


async def _send_raw(manager: ConnectionManager, character_id: uuid.UUID, payload: str) -> None:
    ws = manager.get_socket(character_id)
    if ws is None:
        return
    try:
        await ws.send(payload)
    except ConnectionClosed:
        pass


async def broadcast_global(manager: ConnectionManager, message: dict) -> None:
    # Usado apenas para mensagens de sistema/admin
    payload = json.dumps(message)
    # Snapshot para evitar mutação durante iteração
    character_ids = list(manager._connections.keys())
    await asyncio.gather(
        *(_send_raw(manager, cid, payload) for cid in character_ids),
        return_exceptions=True,
    )
