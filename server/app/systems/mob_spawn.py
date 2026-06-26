import asyncio
import json
import random
import uuid

import structlog

from app.data.loader import get_maps, get_monsters
from app.redis_client import get_redis

logger = structlog.get_logger()

DROP_EXPIRE_SECONDS = 300  # drops somem após 5 min

# Mantém referência forte às tasks de IA. Sem isso o event loop só guarda
# referência fraca e o coletor de lixo pode encerrar os loops silenciosamente.
_AI_TASKS: list[asyncio.Task] = []


def get_map_spawns(map_id: str) -> list:
    """Spawns de um mapa, combinando os definidos no mapa (legado, spawn_points)
    e os definidos em cada monstro (campo 'spawns' do cadastro do monstro)."""
    spawns: list = []
    map_data = get_maps().get(map_id, {})
    for sp in map_data.get("spawn_points", []):
        spawns.append({
            "mob_id": sp["mob_id"],
            "count": sp.get("count", 1),
            "respawn_seconds": sp.get("respawn_seconds", 30),
            "area": sp.get("area", {}),
        })
    for mob_id, mob in get_monsters().items():
        mob_respawn = int(mob.get("respawn_seconds", 10))  # CD do cadastro do monstro
        for sp in mob.get("spawns", []):
            if sp.get("map_id") == map_id:
                spawns.append({
                    "mob_id": mob_id,
                    "count": sp.get("count", 1),
                    "respawn_seconds": sp.get("respawn_seconds", mob_respawn),
                    "area": sp.get("area", {}),
                })
    return spawns


async def _clear_map_mobs(map_id: str, r) -> None:
    """Remove instâncias de mobs antigas do Redis (evita acúmulo a cada restart)."""
    mob_ids = await r.smembers(f"map_mobs:{map_id}")
    if mob_ids:
        pipe = r.pipeline()
        for iid in mob_ids:
            pipe.delete(f"mob:{iid}")
        pipe.delete(f"map_mobs:{map_id}")
        await pipe.execute()


async def initialize_all_maps() -> None:
    """Spawna mobs iniciais em todos os mapas e inicia os loops de IA."""
    from app.systems.mob_ai import run_map_ai_loop

    r = get_redis()
    for map_id in get_maps():
        spawns = get_map_spawns(map_id)
        if not spawns:
            continue
        await _clear_map_mobs(map_id, r)   # limpa mobs antigos antes de spawnar os novos
        await spawn_map_mobs(map_id, spawns)
        _AI_TASKS.append(asyncio.create_task(run_map_ai_loop(map_id), name=f"ai_{map_id}"))

    logger.info("mob_ai_started", maps=len(_AI_TASKS))


async def spawn_map_mobs(map_id: str, spawns: list) -> None:
    for sp in spawns:
        for _ in range(int(sp.get("count", 1))):
            await _spawn_mob(map_id, sp["mob_id"], sp.get("area", {}))


async def _spawn_mob(map_id: str, mob_id: str, area: dict) -> str:
    monsters = get_monsters()
    mob_data = monsters.get(mob_id)
    if not mob_data:
        logger.warning("spawn_unknown_mob", mob_id=mob_id)
        return ""

    instance_id = str(uuid.uuid4())
    x1 = float(area.get("x1", 0.0)); x2 = float(area.get("x2", 0.0))
    y1 = float(area.get("y1", 0.0)); y2 = float(area.get("y2", 0.0))
    x = random.uniform(x1, x2)
    y = random.uniform(y1, y2)
    cx = (x1 + x2) / 2
    cy = (y1 + y2) / 2

    r = get_redis()
    await r.hset(f"mob:{instance_id}", mapping={
        "mob_id": mob_id,
        "map_id": map_id,
        "hp": str(mob_data["hp_max"]),
        "hp_max": str(mob_data["hp_max"]),
        "x": str(x),
        "y": str(y),
        "state": "idle",
        "target_id": "",
        "last_attack": "0",
        "next_wander": "0",
        "wander_tx": str(x),
        "wander_ty": str(y),
        "spawn_area": json.dumps(area),
        "spawn_cx": str(cx),
        "spawn_cy": str(cy),
    })
    await r.sadd(f"map_mobs:{map_id}", instance_id)

    logger.debug("mob_spawned", instance_id=instance_id, mob_id=mob_id, map_id=map_id)
    return instance_id


async def respawn_mob_later(mob_id: str, map_id: str, area: dict, delay: int) -> None:
    await asyncio.sleep(delay)
    instance_id = await _spawn_mob(map_id, mob_id, area)
    if instance_id:
        from app.ws.broadcaster import broadcast_map
        from app.ws.manager import manager
        mob_data = get_monsters().get(mob_id, {})
        r = get_redis()
        mob_raw = await r.hgetall(f"mob:{instance_id}")
        # O cliente espera payload.mobs (lista) — mesma forma do send_map_state
        await broadcast_map(manager, map_id, {
            "type": "MOB_SPAWN",
            "payload": {"mobs": [{
                "instance_id": instance_id,
                "mob_id": mob_id,
                "name": mob_data.get("name", mob_id),
                "ai_type": mob_data.get("ai_type", "passive"),
                "hp": mob_data.get("hp_max", 1),
                "hp_max": mob_data.get("hp_max", 1),
                "x": float(mob_raw.get("x", 0)),
                "y": float(mob_raw.get("y", 0)),
            }]},
        })


async def save_drops_to_redis(
    map_id: str,
    drops: list,
    x: float,
    y: float,
    mob_id: str,
) -> list[dict]:
    if not drops:
        return []

    r = get_redis()
    drop_dicts = []
    pipe = r.pipeline()

    for drop in drops:
        d = drop.to_dict(x, y)
        d["mob_id"] = mob_id
        drop_dicts.append(d)
        pipe.hset(f"drop:{d['drop_id']}", mapping={
            k: json.dumps(v) if isinstance(v, (list, dict)) else str(v)
            for k, v in d.items()
        })
        pipe.expire(f"drop:{d['drop_id']}", DROP_EXPIRE_SECONDS)
        pipe.sadd(f"map_drops:{map_id}", d["drop_id"])

    await pipe.execute()
    return drop_dicts
