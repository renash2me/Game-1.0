from datetime import date, datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.data.loader import get_quests
from app.models.character import Character
from app.models.quest import Quest


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _init_progress(objectives: list) -> dict:
    """Cria estrutura de progresso inicial a partir dos objetivos do catálogo."""
    progress: dict = {"objectives": []}
    for obj in objectives:
        entry = dict(obj)
        entry["current"] = 0
        if obj["type"] == "visit_map":
            entry["visited"] = False
        progress["objectives"].append(entry)
    return progress


def _is_complete(progress: dict) -> bool:
    for obj in progress.get("objectives", []):
        if obj["type"] == "kill_mob":
            if obj.get("current", 0) < obj.get("count", 1):
                return False
        elif obj["type"] == "visit_map":
            if not obj.get("visited", False):
                return False
    return True


def _meets_requirements(character: Character, quest_data: dict) -> bool:
    req = quest_data.get("requirements", {})
    if character.level < req.get("level", 1):
        return False
    return True


def _can_accept_daily(record: Quest | None) -> bool:
    """Daily pode ser aceita novamente se o último completion foi antes de hoje."""
    if record is None:
        return True
    if record.status == "active":
        return False
    if record.status == "completed" and record.completed_at:
        return record.completed_at.date() < _today()
    return True


# ── Queries ───────────────────────────────────────────────────────────────────

async def get_quest_record(
    character_id, quest_id: str, session: AsyncSession
) -> Quest | None:
    result = await session.execute(
        select(Quest).where(
            Quest.character_id == character_id,
            Quest.quest_id == quest_id,
        )
    )
    return result.scalar_one_or_none()


# ── Accept ────────────────────────────────────────────────────────────────────

async def accept_quest(
    character: Character, quest_id: str, session: AsyncSession
) -> tuple[Quest | None, str]:
    catalog = get_quests()
    quest_data = catalog.get(quest_id)
    if not quest_data:
        return None, "Quest não encontrada no catálogo"

    if not _meets_requirements(character, quest_data):
        req_level = quest_data.get("requirements", {}).get("level", 1)
        return None, f"Requer nível {req_level}"

    is_daily = quest_data.get("type") == "daily"
    record = await get_quest_record(character.id, quest_id, session)

    if record:
        if record.status == "active":
            return None, "Quest já está ativa"
        if record.status == "completed" and not is_daily:
            return None, "Quest já foi completada"
        if is_daily and not _can_accept_daily(record):
            return None, "Quest diária já foi completada hoje"

        # Reativar daily
        record.status = "active"
        record.progress = _init_progress(quest_data.get("objectives", []))
        record.accepted_at = datetime.now(timezone.utc)
        record.completed_at = None
    else:
        record = Quest(
            character_id=character.id,
            quest_id=quest_id,
            status="active",
            progress=_init_progress(quest_data.get("objectives", [])),
            accepted_at=datetime.now(timezone.utc),
        )
        session.add(record)

    return record, ""


# ── Progress ──────────────────────────────────────────────────────────────────

async def update_kill_progress(
    character_id, mob_id: str, session: AsyncSession
) -> list[str]:
    """Atualiza quests ativas com objetivo kill_mob. Retorna IDs das completadas."""
    result = await session.execute(
        select(Quest).where(
            Quest.character_id == character_id,
            Quest.status == "active",
        )
    )
    active = result.scalars().all()
    completed_ids: list[str] = []

    for record in active:
        changed = False
        progress = dict(record.progress)
        objectives = list(progress.get("objectives", []))

        for obj in objectives:
            if obj["type"] == "kill_mob" and obj["mob_id"] == mob_id:
                if obj.get("current", 0) < obj.get("count", 1):
                    obj["current"] = obj.get("current", 0) + 1
                    changed = True

        if changed:
            progress["objectives"] = objectives
            record.progress = progress

            if _is_complete(progress):
                completed_ids.append(record.quest_id)

    return completed_ids


async def update_map_progress(
    character_id, map_id: str, session: AsyncSession
) -> list[str]:
    """Atualiza quests ativas com objetivo visit_map. Retorna IDs das completadas."""
    result = await session.execute(
        select(Quest).where(
            Quest.character_id == character_id,
            Quest.status == "active",
        )
    )
    active = result.scalars().all()
    completed_ids: list[str] = []

    for record in active:
        changed = False
        progress = dict(record.progress)
        objectives = list(progress.get("objectives", []))

        for obj in objectives:
            if obj["type"] == "visit_map" and obj["map_id"] == map_id:
                if not obj.get("visited", False):
                    obj["visited"] = True
                    obj["current"] = 1
                    changed = True

        if changed:
            progress["objectives"] = objectives
            record.progress = progress

            if _is_complete(progress):
                completed_ids.append(record.quest_id)

    return completed_ids


# ── Deliver ───────────────────────────────────────────────────────────────────

async def deliver_quest(
    character: Character, quest_id: str, session: AsyncSession
) -> tuple[dict | None, str]:
    catalog = get_quests()
    quest_data = catalog.get(quest_id)
    if not quest_data:
        return None, "Quest não encontrada"

    record = await get_quest_record(character.id, quest_id, session)
    if not record or record.status != "active":
        return None, "Quest não está ativa"

    if not _is_complete(record.progress):
        return None, "Objetivos ainda não foram completados"

    # Streak para quests diárias
    if quest_data.get("type") == "daily":
        yesterday = _today().toordinal() - 1
        if record.completed_at and record.completed_at.date().toordinal() == yesterday:
            record.daily_streak += 1
        else:
            record.daily_streak = 1

    record.status = "completed"
    record.completed_at = datetime.now(timezone.utc)

    # Recompensas
    rewards = quest_data.get("rewards", {})
    xp_reward = rewards.get("xp", 0)
    zeny_reward = rewards.get("zeny", 0)
    item_rewards = rewards.get("items", [])

    character.zeny += zeny_reward

    from app.systems.xp_level import check_level_up
    leveled_up = False
    new_level = character.level

    if xp_reward > 0:
        new_xp = character.xp + xp_reward
        new_level, new_xp, new_xp_to_next, sp, skp = check_level_up(
            character.level, new_xp, character.xp_to_next
        )
        character.xp = new_xp
        character.xp_to_next = new_xp_to_next
        if new_level > character.level:
            character.level = new_level
            character.stat_points += sp
            character.skill_points += skp
            leveled_up = True

    return {
        "quest_id": quest_id,
        "xp": xp_reward,
        "zeny": zeny_reward,
        "items": item_rewards,
        "daily_streak": record.daily_streak,
        "leveled_up": leveled_up,
        "new_level": new_level,
    }, ""
