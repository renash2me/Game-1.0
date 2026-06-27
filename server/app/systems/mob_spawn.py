import asyncio
import json
import random
import time
import uuid

import structlog

from app.data.loader import get_maps, get_monsters
from app.redis_client import get_redis

logger = structlog.get_logger()

DROP_EXPIRE_SECONDS = 15  # drops somem do chão após 15s
DROP_OWNER_SECONDS = 10   # preferência do dono dura 10s; depois qualquer um pega

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


async def respawn_all_maps() -> int:
    """Limpa e re-spawna os mobs de todos os mapas conforme a config atual,
    avisando os clientes (MOB_CLEAR + MOB_SPAWN). Usado pelo admin ao salvar."""
    from app.ws.broadcaster import broadcast_map
    from app.ws.manager import manager

    monsters = get_monsters()
    r = get_redis()
    total = 0
    for map_id in get_maps():
        await _clear_map_mobs(map_id, r)
        await broadcast_map(manager, map_id, {"type": "MOB_CLEAR", "payload": {}})

        spawns = get_map_spawns(map_id)
        if not spawns:
            continue
        await spawn_map_mobs(map_id, spawns)

        ids = await r.smembers(f"map_mobs:{map_id}")
        mobs_data = []
        for iid in ids:
            mob_raw = await r.hgetall(f"mob:{iid}")
            if not mob_raw:
                continue
            md = monsters.get(mob_raw.get("mob_id", ""), {})
            mobs_data.append({
                "instance_id": iid,
                "mob_id": mob_raw.get("mob_id"),
                "name": md.get("name", "?"),
                "ai_type": md.get("ai_type", "passive"),
                "hp": int(mob_raw.get("hp", 0)),
                "hp_max": int(mob_raw.get("hp_max", 1)),
                "x": float(mob_raw.get("x", 0)),
                "y": float(mob_raw.get("y", 0)),
            })
            total += 1
        if mobs_data:
            await broadcast_map(manager, map_id, {"type": "MOB_SPAWN", "payload": {"mobs": mobs_data}})

    logger.info("respawn_all_maps", total=total)
    return total


async def _spawn_mob(map_id: str, mob_id: str, area: dict) -> str:
    monsters = get_monsters()
    mob_data = monsters.get(mob_id)
    if not mob_data:
        logger.warning("spawn_unknown_mob", mob_id=mob_id)
        return ""

    instance_id = str(uuid.uuid4())
    x1 = float(area.get("x1", 0.0)); x2 = float(area.get("x2", 0.0))
    y1 = float(area.get("y1", 0.0)); y2 = float(area.get("y2", 0.0))
    # Área sem tamanho (ex.: 0,0,0,0) empilharia tudo num ponto → espalha num
    # box padrão de 400x400 ao redor do centro informado.
    if abs(x2 - x1) < 1.0 and abs(y2 - y1) < 1.0:
        cx0 = (x1 + x2) / 2.0
        cy0 = (y1 + y2) / 2.0
        x1, x2 = cx0 - 200.0, cx0 + 200.0
        y1, y2 = cy0 - 200.0, cy0 + 200.0
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
    owner_id: str = "",
) -> list[dict]:
    if not drops:
        return []

    r = get_redis()
    owner_until = int(time.time() * 1000) + DROP_OWNER_SECONDS * 1000 if owner_id else 0
    drop_dicts = []
    pipe = r.pipeline()

    for drop in drops:
        d = drop.to_dict(x, y)
        d["mob_id"] = mob_id
        d["owner_id"] = owner_id
        d["owner_until"] = owner_until
        drop_dicts.append(d)
        pipe.hset(f"drop:{d['drop_id']}", mapping={
            k: json.dumps(v) if isinstance(v, (list, dict)) else str(v)
            for k, v in d.items()
        })
        pipe.expire(f"drop:{d['drop_id']}", DROP_EXPIRE_SECONDS)
        pipe.sadd(f"map_drops:{map_id}", d["drop_id"])

    await pipe.execute()
    for d in drop_dicts:
        d["ttl"] = DROP_EXPIRE_SECONDS   # vida cheia para o cliente
    return drop_dicts


async def place_ground_drop(
    map_id: str, item_id: str, quantity: int, x: float, y: float, owner_id: str = "",
) -> dict:
    """Cria um drop avulso no chão (ex.: item largado por um jogador). Retorna o payload."""
    r = get_redis()
    owner_until = int(time.time() * 1000) + DROP_OWNER_SECONDS * 1000 if owner_id else 0
    drop_id = str(uuid.uuid4())
    d = {
        "drop_id": drop_id, "item_id": item_id, "quantity": quantity,
        "x": x, "y": y, "cards": [], "owner_id": owner_id, "owner_until": owner_until,
    }
    pipe = r.pipeline()
    pipe.hset(f"drop:{drop_id}", mapping={
        k: json.dumps(v) if isinstance(v, (list, dict)) else str(v) for k, v in d.items()
    })
    pipe.expire(f"drop:{drop_id}", DROP_EXPIRE_SECONDS)
    pipe.sadd(f"map_drops:{map_id}", drop_id)
    await pipe.execute()
    d["ttl"] = DROP_EXPIRE_SECONDS
    return d
