import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_token
from app.database import get_session
from app.models.player import Player

_bearer = HTTPBearer()


async def get_current_player(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> Player:
    exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido ou expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        player_id = uuid.UUID(decode_token(credentials.credentials))
    except (JWTError, ValueError):
        raise exc

    result = await session.execute(select(Player).where(Player.id == player_id))
    player = result.scalar_one_or_none()
    if player is None or not player.is_active:
        raise exc
    return player
