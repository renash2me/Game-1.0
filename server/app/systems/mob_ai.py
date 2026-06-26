import asyncio
import json
import math
import random
import time

import structlog

from app.data.loader import get_monsters
from app.redis_client import get_redis

logger = structlog.get_logger()

TICK = 0.3          # segundos por tick
ATTACK_CD = 1500    # ms entre ataques do mob
WANDER_CD = 3.0     # segundos entre mudanças de destino no wander
WANDER_RADIUS = 150 # pixels máx do centro do spawn ao vagar
CHASE_LEASH = 350   # server units: dist máx do spawn antes do mob desistir e voltar


async def run_map_ai_loop(map_id: str) -> None:
    logger.info("ai_loop_started", map_id=map_id)
    while True:
        try:
            await _tick_map(map_id)
        except Exception as e:
            logger.error("ai_tick_error", map_id=map_id, error=str(e))
        await asyncio.sleep(TICK)


async def _tick_map(map_id: str) -> None:
    r = get_redis()
    instance_ids = await r.smembers(f"map_mobs:{map_id}")
    if not instance_ids:
        return

    now_ms = int(time.time() * 1000)
    now_s = time.time()

    for iid in instance_ids:
        mob_raw = await r.hgetall(f"mob:{iid}")
        if not mob_raw:
            continue
        await _tick_mob(map_id, iid, mob_raw, now_ms, now_s, r)


async def _tick_mob(
    map_id: str,
    instance_id: str,
    mob_raw: dict,
    now_ms: int,
    now_s: float,
    r,
) -> None:
    mob_id = mob_raw["mob_id"]
    mob_data = get_monsters().get(mob_id)
    if not mob_data:
        return

    hp = int(mob_raw["hp"])
    hp_max = int(mob_raw["hp_max"])
    x = float(mob_raw["x"])
    y = float(mob_raw["y"])
    state = mob_raw.get("state", "idle")
    target_id = mob_raw.get("target_id", "")
    last_attack = int(mob_raw.get("last_attack", "0"))
    next_wander = float(mob_raw.get("next_wander", "0"))
    wander_tx = float(mob_raw.get("wander_tx", x))
    wander_ty = float(mob_raw.get("wander_ty", y))
    spawn_area = json.loads(mob_raw.get("spawn_area", "{}"))

    move_speed = float(mob_data.get("move_speed", 60))
    aggro_range = float(mob_data.get("aggro_range", 0))
    attack_range = float(mob_data.get("attack_range", 50))
    ai_type = mob_data.get("ai_type", "passive")
    hp_pct = hp / hp_max if hp_max > 0 else 1.0

    updates: dict = {}

    # ── Transições de estado ────────────────────────────────────────────
    if hp_pct < 0.2 and state not in ("flee", "dead"):
        state = "flee"
        updates["state"] = "flee"
    elif hp_pct >= 0.2 and state == "flee":
        state = "aggro"
        updates["state"] = "aggro"

    # ── IDLE ─────────────────────────────────────────────────────────────
    if state == "idle":
        if ai_type == "aggressive" and aggro_range > 0:
            nearest = await _nearest_player(map_id, x, y, aggro_range, r)
            if nearest:
                state = "aggro"
                target_id = nearest
                updates["state"] = "aggro"
                updates["target_id"] = nearest

        if state == "idle":
            # Wander
            if now_s >= next_wander or _dist(x, y, wander_tx, wander_ty) < 5:
                cx = float(mob_raw.get("spawn_cx", x))
                cy = float(mob_raw.get("spawn_cy", y))
                angle = random.uniform(0, 2 * math.pi)
                radius = random.uniform(0, WANDER_RADIUS)
                wander_tx = cx + math.cos(angle) * radius
                wander_ty = cy + math.sin(angle) * radius
                next_wander = now_s + WANDER_CD + random.uniform(-0.5, 0.5)
                updates["wander_tx"] = str(wander_tx)
                updates["wander_ty"] = str(wander_ty)
                updates["next_wander"] = str(next_wander)

            nx, ny = _step_toward(x, y, wander_tx, wander_ty, move_speed * TICK * 0.5)
            if nx != x or ny != y:
                updates["x"] = str(nx)
                updates["y"] = str(ny)
                await _broadcast_move(map_id, instance_id, nx, ny)

    # ── AGGRO ─────────────────────────────────────────────────────────────
    elif state == "aggro":
        spawn_cx = float(mob_raw.get("spawn_cx", x))
        spawn_cy = float(mob_raw.get("spawn_cy", y))
        if not target_id or _dist(x, y, spawn_cx, spawn_cy) > CHASE_LEASH:
            # sem alvo, ou foi puxado longe demais do território → desiste e volta a vagar
            updates["state"] = "idle"
            updates["target_id"] = ""
        else:
            tpos = await _player_pos(target_id, r)
            if tpos is None:
                updates["state"] = "idle"
                updates["target_id"] = ""
            else:
                tx, ty = tpos
                dist = _dist(x, y, tx, ty)
                if dist <= attack_range:
                    if now_ms - last_attack >= ATTACK_CD:
                        await _mob_attack(map_id, instance_id, mob_data, target_id, now_ms, r)
                        updates["last_attack"] = str(now_ms)
                else:
                    nx, ny = _step_toward(x, y, tx, ty, move_speed * TICK)
                    updates["x"] = str(nx)
                    updates["y"] = str(ny)
                    await _broadcast_move(map_id, instance_id, nx, ny)

    # ── FLEE ─────────────────────────────────────────────────────────────
    elif state == "flee":
        if target_id:
            tpos = await _player_pos(target_id, r)
            if tpos:
                tx, ty = tpos
                nx, ny = _step_away(x, y, tx, ty, move_speed * TICK * 1.5)
                updates["x"] = str(nx)
                updates["y"] = str(ny)
                await _broadcast_move(map_id, instance_id, nx, ny)

    if updates:
        await r.hset(f"mob:{instance_id}", mapping=updates)


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _nearest_player(
    map_id: str, x: float, y: float, max_range: float, r
) -> str | None:
    online = await r.smembers(f"online_players:{map_id}")
    best_id: str | None = None
    best_dist = max_range

    for char_id in online:
        pos = await _player_pos(char_id, r)
        if pos is None:
            continue
        d = _dist(x, y, pos[0], pos[1])
        if d < best_dist:
            best_dist = d
            best_id = char_id

    return best_id


async def _player_pos(char_id: str, r) -> tuple[float, float] | None:
    data = await r.hgetall(f"pos:{char_id}")
    if not data:
        return None
    return float(data["x"]), float(data["y"])


async def _broadcast_move(map_id: str, instance_id: str, x: float, y: float) -> None:
    from app.ws.broadcaster import broadcast_map
    from app.ws.manager import manager
    await broadcast_map(manager, map_id, {
        "type": "MOB_MOVE",
        "payload": {"instance_id": instance_id, "x": x, "y": y},
        "timestamp": int(time.time() * 1000),
    })


async def _mob_attack(
    map_id: str,
    instance_id: str,
    mob_data: dict,
    target_id: str,
    now_ms: int,
    r,
) -> None:
    from app.systems.combat import physical_attack, stats_from_character, stats_from_mob
    from app.ws.broadcaster import broadcast_map, send_to
    from app.ws.manager import manager

    char_raw = await r.hgetall(f"char_stats:{target_id}")
    if not char_raw:
        return

    mob_stats = stats_from_mob(mob_data)
    char_stats = stats_from_character(char_raw)

    damage, is_miss, is_crit = physical_attack(mob_stats, char_stats)

    # Atualiza HP do personagem no Redis
    char_hp = int(char_raw.get("hp", 1))
    char_hp_max = int(char_raw.get("hp_max", 1))
    new_hp = max(0, char_hp - damage)
    await r.hset(f"char_stats:{target_id}", "hp", str(new_hp))

    msg = {
        "type": "DAMAGE",
        "payload": {
            "attacker_id": instance_id,
            "attacker_type": "mob",
            "target_id": target_id,
            "target_type": "player",
            "damage": damage,
            "is_miss": is_miss,
            "is_critical": is_crit,
            "target_hp": new_hp,
            "target_hp_max": char_hp_max,
        },
        "timestamp": now_ms,
    }
    await broadcast_map(manager, map_id, msg)

    logger.debug("mob_attacked", mob=mob_data["id"], target=target_id, dmg=damage)


def _dist(x1: float, y1: float, x2: float, y2: float) -> float:
    return math.hypot(x2 - x1, y2 - y1)


def _step_toward(x: float, y: float, tx: float, ty: float, speed: float) -> tuple[float, float]:
    d = _dist(x, y, tx, ty)
    if d <= speed:
        return tx, ty
    ratio = speed / d
    return x + (tx - x) * ratio, y + (ty - y) * ratio


def _step_away(x: float, y: float, tx: float, ty: float, speed: float) -> tuple[float, float]:
    d = _dist(x, y, tx, ty)
    if d < 1:
        return x + speed, y
    ratio = speed / d
    return x - (tx - x) * ratio, y - (ty - y) * ratio
