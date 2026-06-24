import uuid
from collections import defaultdict

import structlog
from websockets.server import WebSocketServerProtocol

logger = structlog.get_logger()


class ConnectionManager:
    def __init__(self) -> None:
        # character_id → websocket
        self._connections: dict[uuid.UUID, WebSocketServerProtocol] = {}
        # map_id → set of character_ids
        self._map_rooms: dict[str, set[uuid.UUID]] = defaultdict(set)
        # character_id → map_id
        self._character_map: dict[uuid.UUID, str] = {}

    async def connect(self, character_id: uuid.UUID, websocket: WebSocketServerProtocol) -> None:
        self._connections[character_id] = websocket
        logger.info("ws_connected", character_id=str(character_id), total=len(self._connections))

    async def disconnect(self, character_id: uuid.UUID) -> None:
        self._connections.pop(character_id, None)
        map_id = self._character_map.pop(character_id, None)
        if map_id:
            self._map_rooms[map_id].discard(character_id)
        logger.info("ws_disconnected", character_id=str(character_id), total=len(self._connections))

    def join_map(self, character_id: uuid.UUID, map_id: str) -> None:
        old_map = self._character_map.get(character_id)
        if old_map and old_map != map_id:
            self._map_rooms[old_map].discard(character_id)
        self._map_rooms[map_id].add(character_id)
        self._character_map[character_id] = map_id

    def get_map(self, character_id: uuid.UUID) -> str | None:
        return self._character_map.get(character_id)

    def get_map_members(self, map_id: str) -> set[uuid.UUID]:
        return self._map_rooms.get(map_id, set()).copy()

    def get_socket(self, character_id: uuid.UUID) -> WebSocketServerProtocol | None:
        return self._connections.get(character_id)

    def is_online(self, character_id: uuid.UUID) -> bool:
        return character_id in self._connections

    def online_count(self) -> int:
        return len(self._connections)
