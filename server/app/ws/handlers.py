import asyncio
import json
import time
import uuid

import structlog
from websockets.server import WebSocketServerProtocol

from app.ws.broadcaster import broadcast_map, send_to
from app.ws.connection_manager import ConnectionManager

logger = structlog.get_logger()

# Canais de chat válidos
CHAT_CHANNELS = {"global", "local", "party", "guild", "whisper"}


async def handle_auth(websocket: WebSocketServerProtocol, raw: str) -> uuid.UUID | None:
    """
    Primeira mensagem obrigatória: AUTH com JWT + character_id.
    Formato: {"type": "AUTH", "payload": {"token": "...", "character_id": "..."}}
    """
    from app.core.security import decode_token
    from app.database import async_session_factory
    from app.models.character import Character
    from app.models.player import Player
    from sqlalchemy import select
    from jose import JWTError

    try:
        msg = json.loads(raw)
        if msg.get("type") != "AUTH":
            await websocket.close(4002, "Primeira mensagem deve ser AUTH")
            return None

        payload = msg.get("payload", {})
        token: str = payload.get("token", "")
        char_id_str: str = payload.get("character_id", "")

        player_id = uuid.UUID(decode_token(token))
        character_id = uuid.UUID(char_id_str)

    except (JWTError, ValueError, KeyError, json.JSONDecodeError):
        await websocket.close(4003, "Auth inválida")
        return None

    async with async_session_factory() as session:
        result = await session.execute(
            select(Character).where(
                Character.id == character_id,
                Character.player_id == player_id,
            )
        )
        character = result.scalar_one_or_none()

    if character is None:
        await websocket.close(4004, "Personagem não encontrado")
        return None

    await websocket.send(json.dumps({
        "type": "AUTH_OK",
        "payload": {
            "character_id": str(character_id),
            "map_id": character.current_map,
            "pos_x": character.pos_x,
            "pos_y": character.pos_y,
        },
        "timestamp": _now(),
    }))

    logger.info("ws_auth_ok", character_id=str(character_id), map_id=character.current_map)
    return character_id


async def dispatch(manager: ConnectionManager, character_id: uuid.UUID, raw: str) -> None:
    try:
        msg = json.loads(raw)
    except json.JSONDecodeError:
        return

    msg_type: str = msg.get("type", "")
    payload: dict = msg.get("payload", {})

    match msg_type:
        case "MOVE":
            await _handle_move(manager, character_id, payload)
        case "CHAT":
            await _handle_chat(manager, character_id, payload)
        case _:
            logger.debug("ws_unknown_type", type=msg_type, character_id=str(character_id))


async def _handle_move(
    manager: ConnectionManager,
    character_id: uuid.UUID,
    payload: dict,
) -> None:
    try:
        x = float(payload["x"])
        y = float(payload["y"])
        map_id = str(payload["map_id"])
    except (KeyError, ValueError, TypeError):
        return

    # Garante que o personagem está na room correta
    manager.join_map(character_id, map_id)

    # Persiste posição no Redis (fire-and-forget, sem await)
    asyncio.ensure_future(_persist_position(character_id, map_id, x, y))

    # Broadcast para todos no mapa, exceto quem se moveu
    await broadcast_map(
        manager,
        map_id,
        {
            "type": "PLAYER_MOVE",
            "payload": {
                "character_id": str(character_id),
                "x": x,
                "y": y,
                "map_id": map_id,
            },
            "timestamp": _now(),
        },
        exclude=character_id,
    )


async def _handle_chat(
    manager: ConnectionManager,
    character_id: uuid.UUID,
    payload: dict,
) -> None:
    try:
        channel = str(payload["channel"])
        content = str(payload["content"]).strip()
    except (KeyError, TypeError):
        return

    if channel not in CHAT_CHANNELS or not content or len(content) > 255:
        return

    message = {
        "type": "CHAT_MESSAGE",
        "payload": {
            "character_id": str(character_id),
            "channel": channel,
            "content": content,
        },
        "timestamp": _now(),
    }

    match channel:
        case "global":
            from app.ws.broadcaster import broadcast_global
            await broadcast_global(manager, message)
        case "local":
            map_id = manager.get_map(character_id)
            if map_id:
                await broadcast_map(manager, map_id, message)
        case "whisper":
            target_id_str = payload.get("target_id", "")
            try:
                target_id = uuid.UUID(target_id_str)
                await send_to(manager, target_id, message)
                await send_to(manager, character_id, message)
            except ValueError:
                pass
        case _:
            # party e guild: implementados nas etapas de guilds/party
            pass


async def _persist_position(
    character_id: uuid.UUID,
    map_id: str,
    x: float,
    y: float,
) -> None:
    from app.redis_client import get_redis
    r = get_redis()
    await r.hset(
        f"pos:{character_id}",
        mapping={"map_id": map_id, "x": str(x), "y": str(y)},
    )
    await r.sadd(f"online_players:{map_id}", str(character_id))


def _now() -> int:
    return int(time.time() * 1000)
