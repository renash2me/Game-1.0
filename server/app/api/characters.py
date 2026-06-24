import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_current_player
from app.database import get_session
from app.models.character import Character
from app.models.player import Player
from app.schemas.character import CharacterCreate, CharacterResponse

router = APIRouter(prefix="/api/characters", tags=["characters"])

MAX_CHARACTERS = 9


@router.post("/", response_model=CharacterResponse, status_code=status.HTTP_201_CREATED)
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

    character = Character(player_id=player.id, name=body.name, class_id=body.class_id)
    session.add(character)
    await session.commit()
    await session.refresh(character)
    return character


@router.get("/", response_model=list[CharacterResponse])
async def list_characters(
    player: Player = Depends(get_current_player),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Character).where(Character.player_id == player.id)
    )
    return result.scalars().all()


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
