"""Regeneração natural de HP/SP ao longo do tempo.

A cada tick, os personagens online recuperam HP/SP segundo as fórmulas
hp_regen / sp_regen. De pé, a regeneração ocorre em ticks alternados; sentado
(estado 'sitting'), ocorre todo tick e com bônus — mais rápido, como no RO.
"""
import asyncio

import structlog

logger = structlog.get_logger()

TICK = 2.0           # segundos por tick do loop
STAND_EVERY = 2      # de pé regenera a cada 2 ticks (4s); sentado a cada tick (2s)
SIT_MULTIPLIER = 1.5  # bônus de regeneração ao sentar


async def regen_loop() -> None:
    logger.info("regen_loop_started")
    tick = 0
    while True:
        await asyncio.sleep(TICK)
        tick += 1
        try:
            await _regen_all(tick)
        except Exception:
            logger.exception("regen_loop_error")


async def _regen_all(tick: int) -> None:
    from app.ws.manager import manager
    from app.ws.broadcaster import send_to
    from app.redis_client import get_redis
    from app.systems.formulas import derive_stats

    character_ids = list(manager._connections.keys())
    if not character_ids:
        return

    r = get_redis()
    for cid in character_ids:
        try:
            c = await r.hgetall(f"char_stats:{cid}")
            if not c:
                continue

            hp = int(c.get("hp", 0))
            hp_max = int(c.get("hp_max", 1))
            sp = int(c.get("sp", 0))
            sp_max = int(c.get("sp_max", 1))

            if hp <= 0:
                continue  # morto não regenera
            if hp >= hp_max and sp >= sp_max:
                continue

            sitting = c.get("sitting", "0") == "1"
            if not sitting and tick % STAND_EVERY != 0:
                continue  # de pé só regenera em ticks alternados

            d = derive_stats(
                level=int(c.get("level", 1)), str_=int(c.get("str_stat", 1)),
                agi=int(c.get("agi", 1)), vit=int(c.get("vit", 1)),
                int_=int(c.get("int_stat", 1)), dex=int(c.get("dex", 1)), luk=int(c.get("luk", 1)),
            )
            hp_gain = max(1, int(d.get("hp_regen", 1)))
            sp_gain = max(1, int(d.get("sp_regen", 1)))
            if sitting:
                hp_gain = int(hp_gain * SIT_MULTIPLIER)
                sp_gain = int(sp_gain * SIT_MULTIPLIER)

            new_hp = min(hp_max, hp + hp_gain)
            new_sp = min(sp_max, sp + sp_gain)
            if new_hp == hp and new_sp == sp:
                continue

            await r.hset(f"char_stats:{cid}", mapping={"hp": str(new_hp), "sp": str(new_sp)})
            await send_to(manager, cid, {
                "type": "STATS_UPDATE",
                "payload": {"hp": new_hp, "hp_max": hp_max, "sp": new_sp, "sp_max": sp_max},
            })
        except Exception:
            logger.exception("regen_error", character_id=str(cid))
