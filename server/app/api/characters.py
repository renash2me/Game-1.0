import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_current_player
from app.data import loader
from app.database import get_session
from app.models.character import Character
from app.models.player import Player
from app.systems.formulas import apply_derived
from app.schemas.character import (
    AllocateSkillRequest,
    AllocateStatsRequest,
    CharacterCreate,
    CharacterResponse,
    ClassChangeRequest,
)

router = APIRouter(prefix="/api/characters", tags=["characters"])


async def _sync_redis_stats(character) -> None:
    """Sincroniza o cache char_stats no Redis (combat e regen leem de lá).
    Sem isso, alocar atributos atualiza só o banco e o cache fica defasado —
    o loop de regen acabaria revertendo o HP/SP máx exibido no cliente."""
    try:
        from app.redis_client import get_redis
        r = get_redis()
        if not await r.exists(f"char_stats:{character.id}"):
            return
        await r.hset(f"char_stats:{character.id}", mapping={
            "level": str(character.level),
            "str_stat": str(character.str_stat), "agi": str(character.agi),
            "vit": str(character.vit), "int_stat": str(character.int_stat),
            "dex": str(character.dex), "luk": str(character.luk),
            "stat_points": str(character.stat_points),
            "skill_points": str(character.skill_points),
            "hp": str(character.hp), "hp_max": str(character.hp_max),
            "sp": str(character.sp), "sp_max": str(character.sp_max),
        })
    except Exception:
        pass


def _check_class_requirements(target_class: dict, character: Character) -> None:
    req = target_class.get("requirements", {})

    level_req = req.get("level", 0)
    if character.level < level_req:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Nível insuficiente: precisa de {level_req}, você tem {character.level}",
        )

    class_id_req = req.get("class_id")
    class_id_any = req.get("class_id_any", [])
    if class_id_req and character.class_id != class_id_req:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Classe atual incompatível: precisa ser '{class_id_req}'",
        )
    if class_id_any and character.class_id not in class_id_any:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Classe atual incompatível com os requisitos desta evolução",
        )

    aptitude_min = req.get("aptitude_min", {})
    aptitude = character.aptitude_data or {}
    for key, minimum in aptitude_min.items():
        if aptitude.get(key, 0) < minimum:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Requisitos não atendidos para esta classe",
            )

MAX_CHARACTERS = 9


@router.get("/classes")
async def list_public_classes() -> list[dict]:
    """Retorna todas as classes não-secretas para referência do cliente."""
    classes = loader.get_classes()
    return [
        {k: v for k, v in cls.items() if k != "requirements"}
        for cls in classes.values()
        if not cls.get("is_secret", False)
    ]


@router.post("", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
async def create_character(
    body: CharacterCreate,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    count_result = await session.execute(
        select(Character).where(Character.player_id == player.id)
    )
    if len(count_result.scalars().all()) >= MAX_CHARACTERS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Limite de {MAX_CHARACTERS} personagens por conta atingido",
        )

    name_check = await session.execute(select(Character).where(Character.name == body.name))
    if name_check.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Nome de personagem já em uso")

    character = Character(player_id=player.id, name=body.name, class_id=body.class_id, stat_points=10)
    session.add(character)
    await session.flush()        # aplica defaults (level=1, atributos=1) antes de derivar
    apply_derived(character)
    character.hp = character.hp_max   # nasce com vida/mana cheias
    character.sp = character.sp_max
    await session.commit()
    await session.refresh(character)
    return character


@router.delete("/{character_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_character(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    """Exclui permanentemente o personagem e TODOS os seus dados
    (itens do inventário, quests). Dinheiro/atributos vão junto no registro."""
    from sqlalchemy import delete as sa_delete
    from app.models.inventory import InventoryItem
    from app.models.quest import Quest

    result = await session.execute(
        select(Character).where(Character.id == character_id, Character.player_id == player.id)
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    await session.execute(sa_delete(InventoryItem).where(InventoryItem.character_id == character_id))
    await session.execute(sa_delete(Quest).where(Quest.character_id == character_id))
    await session.delete(character)
    await session.commit()

    # Limpeza best-effort no Redis (caso houvesse cache)
    try:
        from app.redis_client import get_redis
        r = get_redis()
        await r.delete(f"char_stats:{character_id}", f"pos:{character_id}")
    except Exception:
        pass


@router.get("", response_model=list[CharacterResponse])
async def list_characters(
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(Character.player_id == player.id)
    )
    return result.scalars().all()


@router.get("/{character_id}/available-classes")
async def get_available_classes(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    """Retorna as classes para as quais o personagem pode evoluir agora."""
    result = await session.execute(
        select(Character).where(Character.id == character_id, Character.player_id == player.id)
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    classes = loader.get_classes()
    available = []
    for cls in classes.values():
        if cls.get("evolves_from") != character.class_id:
            continue
        req = cls.get("requirements", {})
        if character.level < req.get("level", 0):
            continue
        class_id_any = req.get("class_id_any", [])
        if class_id_any and character.class_id not in class_id_any:
            continue
        if cls.get("is_secret"):
            aptitude = character.aptitude_data or {}
            if not all(aptitude.get(k, 0) >= v for k, v in req.get("aptitude_min", {}).items()):
                continue
        available.append({
            "id": cls["id"],
            "name": cls["name"],
            "tier": cls["tier"],
            "is_secret": cls.get("is_secret", False),
            "hp_per_level": cls.get("hp_per_level", 5),
            "sp_per_level": cls.get("sp_per_level", 2),
            "stat_growth": cls.get("stat_growth", {}),
            "evolutions": cls.get("evolutions", []),
        })
    return available


@router.get("/{character_id}/skills")
async def list_character_skills(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(
            Character.id == character_id,
            Character.player_id == player.id,
        )
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    catalog = loader.get_skills()
    skills_data = character.skills_data or {}

    available = []
    for skill_id, skill in catalog.items():
        required_class = skill.get("class_required")
        if required_class is None or required_class == character.class_id:
            available.append({**skill, "current_level": skills_data.get(skill_id, 0)})
    return available


@router.get("/{character_id}", response_model=CharacterResponse)
async def get_character(
    character_id: uuid.UUID,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(
            Character.id == character_id,
            Character.player_id == player.id,
        )
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")
    return character


@router.post("/{character_id}/class-change", response_model=CharacterResponse)
async def class_change(
    character_id: uuid.UUID,
    body: ClassChangeRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(Character.id == character_id, Character.player_id == player.id)
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    classes = loader.get_classes()
    target = classes.get(body.class_id)
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Classe não encontrada")

    _check_class_requirements(target, character)

    character.class_id = target["id"]
    character.class_tier = target["tier"]
    apply_derived(character)

    await session.commit()
    await session.refresh(character)
    await _sync_redis_stats(character)
    return character


@router.post("/{character_id}/allocate-stats", response_model=CharacterResponse)
async def allocate_stats(
    character_id: uuid.UUID,
    body: AllocateStatsRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(Character.id == character_id, Character.player_id == player.id)
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    total = body.str + body.agi + body.vit + body.int_ + body.dex + body.luk
    if total == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Nenhum ponto a alocar")
    if total > character.stat_points:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Pontos insuficientes: disponível {character.stat_points}, necessário {total}",
        )

    character.str_stat += body.str
    character.agi += body.agi
    character.vit += body.vit
    character.int_stat += body.int_
    character.dex += body.dex
    character.luk += body.luk
    character.stat_points -= total

    apply_derived(character)

    await session.commit()
    await session.refresh(character)
    await _sync_redis_stats(character)
    return character


@router.post("/{character_id}/allocate-skill", response_model=CharacterResponse)
async def allocate_skill(
    character_id: uuid.UUID,
    body: AllocateSkillRequest,
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(Character.id == character_id, Character.player_id == player.id)
    )
    character = result.scalar_one_or_none()
    if not character:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Personagem não encontrado")

    skills = loader.get_skills()
    skill = skills.get(body.skill_id)
    if not skill:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Habilidade não encontrada")

    skill_class = skill.get("class_required")
    if skill_class and skill_class != character.class_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Esta habilidade requer a classe '{skill_class}'",
        )

    current_level = (character.skills_data or {}).get(body.skill_id, 0)
    max_level = skill.get("max_level", 10)
    if current_level >= max_level:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Habilidade já está no nível máximo ({max_level})",
        )

    levels_to_add = min(body.levels, max_level - current_level)
    if levels_to_add > character.skill_points:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Pontos de habilidade insuficientes: disponível {character.skill_points}",
        )

    new_skills = dict(character.skills_data or {})
    new_skills[body.skill_id] = current_level + levels_to_add
    character.skills_data = new_skills
    character.skill_points -= levels_to_add

    await session.commit()
    await session.refresh(character)
    return character
