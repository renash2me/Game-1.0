import asyncio
import structlog

logger = structlog.get_logger()

SAVE_INTERVAL = 120  # segundos entre cada flush para o banco


async def periodic_checkpoint() -> None:
    """Salva stats dos personagens online do Redis para o Postgres a cada SAVE_INTERVAL segundos.
    Garante que XP, nível, posição e HP não sejam perdidos em caso de queda de energia."""
    while True:
        await asyncio.sleep(SAVE_INTERVAL)
        try:
            await _flush_all_online()
        except Exception:
            logger.exception("checkpoint_loop_error")


async def _flush_all_online() -> None:
    from app.ws.manager import manager
    from app.redis_client import get_redis
    from app.database import async_session_factory
    from app.models.character import Character
    from sqlalchemy import select
    import uuid

    character_ids = list(manager._connections.keys())
    if not character_ids:
        return

    r = get_redis()
    saved = 0

    for cid in character_ids:
        try:
            char_raw = await r.hgetall(f"char_stats:{cid}")
            pos = await r.hgetall(f"pos:{cid}")
            if not char_raw:
                continue

            updates: dict = {}
            for int_field in ("xp", "xp_to_next", "level", "stat_points", "skill_points", "hp", "hp_max", "sp", "sp_max"):
                if int_field in char_raw:
                    updates[int_field] = int(char_raw[int_field])
            if pos:
                if "x" in pos:
                    updates["pos_x"] = float(pos["x"])
                if "y" in pos:
                    updates["pos_y"] = float(pos["y"])
                if "map_id" in pos:
                    updates["current_map"] = pos["map_id"]

            if not updates:
                continue

            async with async_session_factory() as session:
                result = await session.execute(select(Character).where(Character.id == cid))
                char = result.scalar_one_or_none()
                if char:
                    for key, val in updates.items():
                        setattr(char, key, val)
                    await session.commit()
                    saved += 1

        except Exception:
            logger.exception("checkpoint_save_error", character_id=str(cid))

    if saved > 0:
        logger.info("checkpoint_done", characters_saved=saved)
