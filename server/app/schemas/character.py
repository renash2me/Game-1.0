import uuid
from datetime import datetime

from pydantic import BaseModel, field_validator


class CharacterCreate(BaseModel):
    name: str
    class_id: str = "novice"

    @field_validator("name")
    @classmethod
    def name_valid(cls, v: str) -> str:
        v = v.strip()
        if not (3 <= len(v) <= 24):
            raise ValueError("Nome deve ter entre 3 e 24 caracteres")
        if not all(c.isalnum() or c == " " for c in v):
            raise ValueError("Nome pode conter apenas letras, números e espaços")
        return v

    @field_validator("class_id")
    @classmethod
    def class_must_be_novice(cls, v: str) -> str:
        if v != "novice":
            raise ValueError("Novos personagens devem começar como novice")
        return v


class ClassChangeRequest(BaseModel):
    class_id: str


class AllocateStatsRequest(BaseModel):
    str: int = 0
    agi: int = 0
    vit: int = 0
    int_: int = 0
    dex: int = 0
    luk: int = 0

    @field_validator("str", "agi", "vit", "int_", "dex", "luk", mode="before")
    @classmethod
    def non_negative(cls, v: int) -> int:
        if v < 0:
            raise ValueError("Pontos de atributo não podem ser negativos")
        return v


class AllocateSkillRequest(BaseModel):
    skill_id: str
    levels: int = 1

    @field_validator("levels")
    @classmethod
    def at_least_one(cls, v: int) -> int:
        if v < 1:
            raise ValueError("levels deve ser >= 1")
        return v


class CharacterResponse(BaseModel):
    id: uuid.UUID
    player_id: uuid.UUID
    name: str
    class_id: str
    class_tier: int
    level: int
    xp: int
    xp_to_next: int
    str_stat: int
    agi: int
    vit: int
    int_stat: int
    dex: int
    luk: int
    stat_points: int
    skill_points: int
    hp: int
    hp_max: int
    sp: int
    sp_max: int
    void_gauge: int
    void_gauge_max: int
    current_map: str
    pos_x: float
    pos_y: float
    zeny: int
    skills_data: dict
    created_at: datetime

    model_config = {"from_attributes": True}
