import asyncio
import json
import time
import uuid

import structlog
from websockets.server import WebSocketServerProtocol

from app.ws.broadcaster import broadcast_map, send_to
from app.ws.connection_manager import ConnectionManager

logger = structlog.get_logger()

CHAT_CHANNELS = {"global", "local", "map", "party", "guild", "whisper"}

# Ponto de renascimento seguro (última cidade segura). Como só há 1 mapa, é fixo.
SAFE_RESPAWN = ("starter_village", 0.0, 0.0)


# ── Auth ─────────────────────────────────────────────────────────────────────

async def handle_auth(websocket: WebSocketServerProtocol, raw: str) -> uuid.UUID | None:
    from app.core.security import decode_token
    from app.database import async_session_factory
    from app.models.character import Character
    from jose import JWTError
    from sqlalchemy import select

    try:
        msg = json.loads(raw)
        if msg.get("type") != "AUTH":
            await websocket.close(4002, "Primeira mensagem deve ser AUTH")
            return None

        payload = msg.get("payload", {})
        player_id = uuid.UUID(decode_token(payload["token"]))
        character_id = uuid.UUID(payload["character_id"])
    except (JWTError, ValueError, KeyError, json.JSONDecodeError):
        await websocket.close(4003, "Auth invalida")
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
            await websocket.close(4004, "Personagem nao encontrado")
            return None
        # Recalcula HP/SP máx pelas fórmulas (aplica alterações feitas no admin)
        from app.systems.formulas import apply_derived
        apply_derived(character)
        if character.hp <= 0:           # nunca entra no jogo morto
            character.hp = character.hp_max
        await session.commit()
        await session.refresh(character)

    # Guarda stats em cache Redis para o loop de IA usar
    await _cache_char_stats(character)

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


async def send_map_state(manager: ConnectionManager, character_id: uuid.UUID) -> None:
    """Envia MAP_PLAYERS e lista de mobs ao entrar no mapa."""
    from app.redis_client import get_redis
    from app.data.loader import get_monsters

    r = get_redis()
    char_raw = await r.hgetall(f"char_stats:{character_id}")
    map_id = char_raw.get("current_map", "starter_village")

    manager.join_map(character_id, map_id)
    await r.sadd(f"online_players:{map_id}", str(character_id))

    # Posição inicial no Redis
    await r.hset(f"pos:{character_id}", mapping={
        "map_id": map_id,
        "x": char_raw.get("pos_x", "0.0"),
        "y": char_raw.get("pos_y", "0.0"),
    })

    # MAP_PLAYERS — outros jogadores no mapa
    members = manager.get_map_members(map_id) - {character_id}
    players_data = []
    for cid in members:
        pos = await r.hgetall(f"pos:{cid}")
        if pos:
            players_data.append({"character_id": str(cid), "x": float(pos["x"]), "y": float(pos["y"])})

    await send_to(manager, character_id, {
        "type": "MAP_PLAYERS",
        "payload": {"players": players_data},
        "timestamp": _now(),
    })

    # MOB_SPAWN — mobs ativos no mapa
    monsters = get_monsters()
    instance_ids = await r.smembers(f"map_mobs:{map_id}")
    mobs_data = []
    for iid in instance_ids:
        mob_raw = await r.hgetall(f"mob:{iid}")
        if not mob_raw:
            continue
        mob_data = monsters.get(mob_raw.get("mob_id", ""), {})
        mobs_data.append({
            "instance_id": iid,
            "mob_id": mob_raw.get("mob_id"),
            "name": mob_data.get("name", "?"),
            "ai_type": mob_data.get("ai_type", "passive"),
            "hp": int(mob_raw.get("hp", 0)),
            "hp_max": int(mob_raw.get("hp_max", 1)),
            "x": float(mob_raw.get("x", 0)),
            "y": float(mob_raw.get("y", 0)),
        })

    if mobs_data:
        await send_to(manager, character_id, {
            "type": "MOB_SPAWN",
            "payload": {"mobs": mobs_data},
            "timestamp": _now(),
        })

    # DROP_APPEAR — drops já no chão (para quem entra/volta ao mapa)
    drop_ids = await r.smembers(f"map_drops:{map_id}")
    for did in drop_ids:
        draw = await r.hgetall(f"drop:{did}")
        if not draw:
            continue
        await send_to(manager, character_id, {
            "type": "DROP_APPEAR",
            "payload": {
                "drop_id": did,
                "item_id": draw.get("item_id", ""),
                "quantity": int(draw.get("quantity", "1")),
                "x": float(draw.get("x", 0)),
                "y": float(draw.get("y", 0)),
            },
            "timestamp": _now(),
        })


# ── Dispatch ─────────────────────────────────────────────────────────────────

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
        case "ATTACK":
            await _handle_attack(manager, character_id, payload)
        case "PICKUP":
            await _handle_pickup(manager, character_id, payload)
        case "CHAT":
            await _handle_chat(manager, character_id, payload)
        case "SIT":
            await _handle_sit(manager, character_id, payload)
        case "RESPAWN":
            await _handle_respawn(manager, character_id, payload)
        case _:
            logger.debug("ws_unknown_type", type=msg_type)


# ── MOVE ─────────────────────────────────────────────────────────────────────

async def _handle_move(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    try:
        x = float(payload["x"])
        y = float(payload["y"])
    except (KeyError, ValueError, TypeError):
        return
    # map_id é opcional: usa o do payload ou o mapa atual conhecido pelo servidor
    map_id = str(payload.get("map_id") or manager.get_map(character_id) or "starter_village")
    logger.debug("move_received", character_id=str(character_id), x=x, y=y, map_id=map_id)

    from app.redis_client import get_redis
    r = get_redis()

    old_map = manager.get_map(character_id)
    map_changed = old_map and old_map != map_id
    if map_changed:
        await r.srem(f"online_players:{old_map}", str(character_id))
        manager.join_map(character_id, map_id)
        await r.sadd(f"online_players:{map_id}", str(character_id))
        await _cache_char_map(character_id, map_id, r)
        await send_map_state(manager, character_id)
        asyncio.ensure_future(_update_quests_on_map(character_id, map_id, manager))
        asyncio.ensure_future(_update_aptitude_on_map(character_id, map_id))
    else:
        manager.join_map(character_id, map_id)

    await r.hset(f"pos:{character_id}", mapping={"map_id": map_id, "x": str(x), "y": str(y)})
    # Mover levanta o personagem (cancela o estado sentado)
    await r.hset(f"char_stats:{character_id}", "sitting", "0")

    await broadcast_map(manager, map_id, {
        "type": "PLAYER_MOVE",
        "payload": {"character_id": str(character_id), "x": x, "y": y, "map_id": map_id},
        "timestamp": _now(),
    }, exclude=character_id)


# ── ATTACK ────────────────────────────────────────────────────────────────────

async def _handle_attack(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    from app.redis_client import get_redis
    from app.systems.combat import physical_attack, stats_from_character, stats_from_mob
    from app.systems.drop_system import roll_drops
    from app.systems.mob_spawn import respawn_mob_later, save_drops_to_redis
    from app.systems.xp_level import check_level_up
    from app.data.loader import get_monsters

    instance_id = str(payload.get("target_id", ""))
    if not instance_id:
        return

    attack_type = str(payload.get("attack_type", "melee"))

    r = get_redis()
    mob_raw = await r.hgetall(f"mob:{instance_id}")
    if not mob_raw or mob_raw.get("state") == "dead":
        return

    map_id = mob_raw.get("map_id", "")
    if manager.get_map(character_id) != map_id:
        return

    # Stats do atacante
    char_raw = await r.hgetall(f"char_stats:{character_id}")
    if not char_raw:
        return

    mob_id = mob_raw["mob_id"]
    mob_data = get_monsters().get(mob_id, {})
    if not mob_data:
        return

    # Atualiza aggro: mob agora persegue o atacante
    await r.hset(f"mob:{instance_id}", mapping={"state": "aggro", "target_id": str(character_id)})

    char_stats = stats_from_character(char_raw)
    mob_stats = stats_from_mob(mob_data)
    damage, is_miss, is_crit = physical_attack(char_stats, mob_stats)

    mob_hp = int(mob_raw["hp"])
    mob_hp_max = int(mob_raw["hp_max"])
    new_hp = max(0, mob_hp - damage)

    await broadcast_map(manager, map_id, {
        "type": "DAMAGE",
        "payload": {
            "attacker_id": str(character_id),
            "attacker_type": "player",
            "target_id": instance_id,
            "target_type": "mob",
            "damage": damage,
            "is_miss": is_miss,
            "is_critical": is_crit,
            "target_hp": new_hp,
            "target_hp_max": mob_hp_max,
        },
        "timestamp": _now(),
    })

    if new_hp <= 0:
        await _handle_mob_death(
            manager, r, character_id, instance_id, mob_id, mob_data, map_id, char_raw,
            mob_x=float(mob_raw.get("x", 0)), mob_y=float(mob_raw.get("y", 0)),
            attack_type=attack_type,
        )
    else:
        await r.hset(f"mob:{instance_id}", "hp", str(new_hp))


async def _handle_mob_death(
    manager: ConnectionManager,
    r,
    killer_id: uuid.UUID,
    instance_id: str,
    mob_id: str,
    mob_data: dict,
    map_id: str,
    char_raw: dict,
    mob_x: float = 0.0,
    mob_y: float = 0.0,
    attack_type: str = "melee",
) -> None:
    from app.systems.drop_system import roll_drops
    from app.systems.mob_spawn import respawn_mob_later, save_drops_to_redis
    from app.systems.xp_level import check_level_up

    # Marca mob como morto e remove do mapa
    await r.hset(f"mob:{instance_id}", "state", "dead")
    await r.srem(f"map_mobs:{map_id}", instance_id)
    await r.delete(f"mob:{instance_id}")

    # Drops — caem na última posição do mob (mob_x/mob_y vêm do chamador)
    drops = roll_drops(mob_data)
    drop_dicts = await save_drops_to_redis(map_id, drops, mob_x, mob_y, mob_id)

    await broadcast_map(manager, map_id, {
        "type": "MOB_DEATH",
        "payload": {
            "instance_id": instance_id,
            "killer_id": str(killer_id),
            "drops": drop_dicts,
        },
        "timestamp": _now(),
    })

    # XP
    base_xp = mob_data.get("base_xp", 0)
    if base_xp > 0:
        level = int(char_raw.get("level", 1))
        xp = int(char_raw.get("xp", 0))
        xp_to_next = int(char_raw.get("xp_to_next", 10))

        new_xp = xp + base_xp
        new_level, new_xp, new_xp_to_next, sp, skp = check_level_up(level, new_xp, xp_to_next)

        updates = {"xp": str(new_xp), "xp_to_next": str(new_xp_to_next)}
        leveled = new_level > level
        new_hp_max = int(char_raw.get("hp_max", 1))
        new_sp_max = int(char_raw.get("sp_max", 1))
        if leveled:
            updates["level"] = str(new_level)
            updates["stat_points"] = str(int(char_raw.get("stat_points", 0)) + sp)
            updates["skill_points"] = str(int(char_raw.get("skill_points", 0)) + skp)
            # Recalcula HP/SP máx no novo level e restaura 100%
            from app.systems.formulas import derive_stats
            d = derive_stats(
                level=new_level,
                str_=int(char_raw.get("str_stat", 1)), agi=int(char_raw.get("agi", 1)),
                vit=int(char_raw.get("vit", 1)), int_=int(char_raw.get("int_stat", 1)),
                dex=int(char_raw.get("dex", 1)), luk=int(char_raw.get("luk", 1)),
            )
            new_hp_max = max(1, int(d.get("max_hp", new_hp_max)))
            new_sp_max = max(1, int(d.get("max_sp", new_sp_max)))
            updates["hp_max"] = str(new_hp_max)
            updates["sp_max"] = str(new_sp_max)
            updates["hp"] = str(new_hp_max)
            updates["sp"] = str(new_sp_max)

        await r.hset(f"char_stats:{killer_id}", mapping=updates)
        await _persist_char_to_db(killer_id, updates)

        if leveled:
            await send_to(manager, killer_id, {
                "type": "LEVEL_UP",
                "payload": {
                    "character_id": str(killer_id),
                    "new_level": new_level,
                    "stat_points_gained": sp,
                    "skill_points_gained": skp,
                    "xp": new_xp,
                    "xp_to_next": new_xp_to_next,
                    "hp": new_hp_max,
                    "hp_max": new_hp_max,
                    "sp": new_sp_max,
                    "sp_max": new_sp_max,
                },
                "timestamp": _now(),
            })
        else:
            # Ganho de XP sem subir de nível: antes não avisava o cliente (barra parada)
            await send_to(manager, killer_id, {
                "type": "XP_GAIN",
                "payload": {
                    "character_id": str(killer_id),
                    "gained": base_xp,
                    "xp": new_xp,
                    "xp_to_next": new_xp_to_next,
                },
                "timestamp": _now(),
            })

    # Quest progress — kill_mob
    damage = int(char_raw.get("damage_dealt_session", 0))
    asyncio.ensure_future(_update_quests_on_kill(killer_id, mob_id, map_id, manager))

    # Aptidão — atualiza de forma assíncrona para não bloquear
    asyncio.ensure_future(_update_aptitude_on_kill(killer_id, damage, mob_data, attack_type))

    # Respawn — usa a fonte combinada (mapa + cadastro do monstro)
    from app.systems.mob_spawn import get_map_spawns
    for sp in get_map_spawns(map_id):
        if sp["mob_id"] == mob_id:
            asyncio.ensure_future(
                respawn_mob_later(mob_id, map_id, sp["area"], sp["respawn_seconds"])
            )
            break


# ── PICKUP ───────────────────────────────────────────────────────────────────

async def _handle_pickup(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    drop_id = str(payload.get("drop_id", ""))
    if not drop_id:
        return

    from app.redis_client import get_redis
    from app.database import async_session_factory
    from app.api.inventory import add_item_to_inventory

    r = get_redis()
    drop_raw = await r.hgetall(f"drop:{drop_id}")
    if not drop_raw:
        return

    map_id = manager.get_map(character_id)
    if not map_id:
        return

    item_id = drop_raw.get("item_id", "")
    quantity = int(drop_raw.get("quantity", "1"))

    # Remove drop do Redis
    await r.delete(f"drop:{drop_id}")
    await r.srem(f"map_drops:{map_id}", drop_id)

    # Adiciona ao inventário no banco
    async with async_session_factory() as session:
        await add_item_to_inventory(character_id, item_id, quantity, session)
        await session.commit()

    await broadcast_map(manager, map_id, {
        "type": "DROP_PICKED",
        "payload": {"drop_id": drop_id, "picker_id": str(character_id)},
        "timestamp": _now(),
    })

    logger.debug("drop_picked", drop_id=drop_id, character_id=str(character_id), item=item_id)


# ── SIT ──────────────────────────────────────────────────────────────────────

async def _handle_sit(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    from app.redis_client import get_redis
    r = get_redis()
    sitting = "1" if payload.get("sitting") else "0"
    await r.hset(f"char_stats:{character_id}", "sitting", sitting)


# ── RESPAWN ──────────────────────────────────────────────────────────────────

async def _handle_respawn(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    """Renasce na cidade segura com HP/SP cheios (acionado pelo botão de morte)."""
    from app.redis_client import get_redis
    r = get_redis()

    c = await r.hgetall(f"char_stats:{character_id}")
    if not c:
        return

    hp_max = int(c.get("hp_max", 1))
    sp_max = int(c.get("sp_max", 1))
    map_id, x, y = SAFE_RESPAWN

    await r.hset(f"char_stats:{character_id}", mapping={
        "hp": str(hp_max), "sp": str(sp_max), "dead": "0",
    })
    await r.hset(f"pos:{character_id}", mapping={"map_id": map_id, "x": str(x), "y": str(y)})

    # Garante que o servidor sabe que ele está no mapa seguro
    old_map = manager.get_map(character_id)
    if old_map != map_id:
        if old_map:
            await r.srem(f"online_players:{old_map}", str(character_id))
        manager.join_map(character_id, map_id)
        await r.sadd(f"online_players:{map_id}", str(character_id))
        await _cache_char_map(character_id, map_id, r)

    await send_to(manager, character_id, {
        "type": "RESPAWN_OK",
        "payload": {
            "map_id": map_id, "x": x, "y": y,
            "hp": hp_max, "hp_max": hp_max, "sp": sp_max, "sp_max": sp_max,
        },
        "timestamp": _now(),
    })
    # Avisa os outros jogadores que ele reapareceu no ponto de renascimento
    await broadcast_map(manager, map_id, {
        "type": "PLAYER_MOVE",
        "payload": {"character_id": str(character_id), "x": x, "y": y, "map_id": map_id},
        "timestamp": _now(),
    }, exclude=character_id)


# ── CHAT ─────────────────────────────────────────────────────────────────────

async def _handle_chat(manager: ConnectionManager, character_id: uuid.UUID, payload: dict) -> None:
    from app.ws.broadcaster import broadcast_global
    from app.redis_client import get_redis

    try:
        channel = str(payload["channel"])
        content = str(payload.get("message", payload.get("content", ""))).strip()
    except (KeyError, TypeError):
        return

    if channel not in CHAT_CHANNELS or not content or len(content) > 255:
        return

    # Resolve nome do remetente via Redis
    r = get_redis()
    char_raw = await r.hgetall(f"char_stats:{character_id}")
    sender_name = char_raw.get("name", "?")

    # "map" é alias de "local"
    effective_channel = "local" if channel == "map" else channel

    message = {
        "type": "CHAT",
        "payload": {
            "channel": channel,
            "sender_name": sender_name,
            "message": content,
        },
        "timestamp": _now(),
    }

    match effective_channel:
        case "global":
            await broadcast_global(manager, message)
        case "local":
            map_id = manager.get_map(character_id)
            if map_id:
                await broadcast_map(manager, map_id, message)
        case "whisper":
            try:
                target_id = uuid.UUID(payload.get("target_id", ""))
                await send_to(manager, target_id, message)
                await send_to(manager, character_id, message)
            except ValueError:
                pass
        case _:
            pass


# ── Quest / Aptidão (fire-and-forget) ─────────────────────────────────────────

async def _update_quests_on_kill(
    character_id: uuid.UUID, mob_id: str, map_id: str, manager: ConnectionManager
) -> None:
    from app.database import async_session_factory
    from app.systems.quest_engine import update_kill_progress
    try:
        async with async_session_factory() as session:
            completed = await update_kill_progress(character_id, mob_id, session)
            await session.commit()
        for quest_id in completed:
            await send_to(manager, character_id, {
                "type": "QUEST_UPDATE",
                "payload": {"quest_id": quest_id, "status": "ready_to_deliver"},
                "timestamp": _now(),
            })
    except Exception as e:
        logger.error("quest_kill_update_error", error=str(e))


async def _update_quests_on_map(
    character_id: uuid.UUID, map_id: str, manager: ConnectionManager
) -> None:
    from app.database import async_session_factory
    from app.systems.quest_engine import update_map_progress
    try:
        async with async_session_factory() as session:
            completed = await update_map_progress(character_id, map_id, session)
            await session.commit()
        for quest_id in completed:
            await send_to(manager, character_id, {
                "type": "QUEST_UPDATE",
                "payload": {"quest_id": quest_id, "status": "ready_to_deliver"},
                "timestamp": _now(),
            })
    except Exception as e:
        logger.error("quest_map_update_error", error=str(e))


async def _update_aptitude_on_kill(
    character_id: uuid.UUID, damage: int, mob_data: dict, attack_type: str
) -> None:
    from app.database import async_session_factory
    from app.models.character import Character
    from app.systems.aptitude import apply_kill_aptitude
    from sqlalchemy import select
    try:
        async with async_session_factory() as session:
            result = await session.execute(select(Character).where(Character.id == character_id))
            char = result.scalar_one_or_none()
            if char and char.class_tier < 4:
                char.aptitude_data = apply_kill_aptitude(
                    char.aptitude_data or {}, mob_data, attack_type, damage
                )
                await session.commit()
    except Exception as e:
        logger.error("aptitude_update_error", error=str(e))


async def _update_aptitude_on_map(character_id: uuid.UUID, map_id: str) -> None:
    from app.database import async_session_factory
    from app.models.character import Character
    from app.data.loader import get_maps
    from app.systems.aptitude import record_map_visit, record_void_map
    from sqlalchemy import select
    try:
        async with async_session_factory() as session:
            result = await session.execute(select(Character).where(Character.id == character_id))
            char = result.scalar_one_or_none()
            if char and char.class_tier < 4:
                apt = record_map_visit(char.aptitude_data or {}, map_id)
                map_data = get_maps().get(map_id, {})
                if "void" in map_data.get("tags", []):
                    apt = record_void_map(apt)
                char.aptitude_data = apt
                await session.commit()
    except Exception as e:
        logger.error("aptitude_map_error", error=str(e))


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _cache_char_stats(character) -> None:
    from app.redis_client import get_redis
    r = get_redis()
    await r.hset(f"char_stats:{character.id}", mapping={
        "name": character.name,
        "level": str(character.level),
        "xp": str(character.xp),
        "xp_to_next": str(character.xp_to_next),
        "str_stat": str(character.str_stat),
        "agi": str(character.agi),
        "vit": str(character.vit),
        "int_stat": str(character.int_stat),
        "dex": str(character.dex),
        "luk": str(character.luk),
        "stat_points": str(character.stat_points),
        "skill_points": str(character.skill_points),
        "hp": str(character.hp),
        "hp_max": str(character.hp_max),
        "sp": str(character.sp),
        "sp_max": str(character.sp_max),
        "current_map": character.current_map,
        "pos_x": str(character.pos_x),
        "pos_y": str(character.pos_y),
        "dead": "0",   # entra sempre vivo (evita flag 'dead' presa = jogador invencível)
    })


async def _cache_char_map(character_id: uuid.UUID, map_id: str, r) -> None:
    await r.hset(f"char_stats:{character_id}", "current_map", map_id)


async def _persist_char_to_db(character_id: uuid.UUID, updates: dict) -> None:
    from app.database import async_session_factory
    from app.models.character import Character
    from sqlalchemy import select

    async with async_session_factory() as session:
        result = await session.execute(select(Character).where(Character.id == character_id))
        char = result.scalar_one_or_none()
        if char:
            if "level" in updates:
                char.level = int(updates["level"])
            if "xp" in updates:
                char.xp = int(updates["xp"])
            if "xp_to_next" in updates:
                char.xp_to_next = int(updates["xp_to_next"])
            if "stat_points" in updates:
                char.stat_points = int(updates["stat_points"])
            if "skill_points" in updates:
                char.skill_points = int(updates["skill_points"])
            if "hp" in updates:
                char.hp = int(updates["hp"])
            if "hp_max" in updates:
                char.hp_max = int(updates["hp_max"])
            if "sp" in updates:
                char.sp = int(updates["sp"])
            if "sp_max" in updates:
                char.sp_max = int(updates["sp_max"])
            await session.commit()


def _now() -> int:
    return int(time.time() * 1000)
