from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.database import get_session
from app.models.player import Player
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, session: AsyncSession = Depends(get_session)):
    existing = await session.execute(
        select(Player).where(
            (Player.username == body.username) | (Player.email == body.email)
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Username ou email já em uso")

    player = Player(
        username=body.username,
        email=body.email,
        password_hash=hash_password(body.password),
    )
    session.add(player)
    await session.commit()
    await session.refresh(player)

    return TokenResponse(
        access_token=create_access_token(str(player.id)),
        expires_in=settings.jwt_expire_hours * 3600,
    )


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(Player).where(Player.username == body.username))
    player = result.scalar_one_or_none()

    if not player or not verify_password(body.password, player.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciais inválidas")

    if not player.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Conta desativada")

    player.last_login = datetime.now(timezone.utc)
    await session.commit()

    return TokenResponse(
        access_token=create_access_token(str(player.id)),
        expires_in=settings.jwt_expire_hours * 3600,
    )
