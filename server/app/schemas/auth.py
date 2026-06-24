import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, field_validator


class RegisterRequest(BaseModel):
    username: str
    email: EmailStr
    password: str

    @field_validator("username")
    @classmethod
    def username_valid(cls, v: str) -> str:
        v = v.strip()
        if not (3 <= len(v) <= 20):
            raise ValueError("Username deve ter entre 3 e 20 caracteres")
        if not v.replace("_", "").isalnum():
            raise ValueError("Username pode conter apenas letras, números e _")
        return v

    @field_validator("password")
    @classmethod
    def password_valid(cls, v: str) -> str:
        if len(v) < 6:
            raise ValueError("Senha deve ter pelo menos 6 caracteres")
        return v


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class PlayerResponse(BaseModel):
    id: uuid.UUID
    username: str
    email: str
    created_at: datetime
    is_active: bool

    model_config = {"from_attributes": True}
