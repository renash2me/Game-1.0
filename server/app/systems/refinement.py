import random
from dataclasses import dataclass

MAX_REFINEMENT = 7

_SUCCESS_RATES: dict[int, float] = {
    0: 1.00,
    1: 1.00,
    2: 1.00,
    3: 1.00,
    4: 0.95,
    5: 0.85,
    6: 0.70,
}

_ZENY_COST: dict[int, int] = {
    0: 100,
    1: 300,
    2: 600,
    3: 1_200,
    4: 2_500,
    5: 5_000,
    6: 10_000,
}

_REFINE_TYPES = {"weapon", "armor", "head", "body", "legs", "feet", "offhand"}


@dataclass(frozen=True)
class RefineResult:
    success: bool
    new_refinement: int
    zeny_cost: int


def zeny_cost(current_level: int) -> int:
    return _ZENY_COST.get(current_level, 0)


def can_refine(item_type: str, current_level: int) -> tuple[bool, str]:
    if item_type not in _REFINE_TYPES:
        return False, "Este tipo de item não pode ser refinado"
    if current_level >= MAX_REFINEMENT:
        return False, f"Refinamento máximo é +{MAX_REFINEMENT}"
    return True, ""


def attempt_refinement(current_level: int) -> RefineResult:
    cost = _ZENY_COST[current_level]
    success = random.random() < _SUCCESS_RATES[current_level]
    return RefineResult(
        success=success,
        new_refinement=current_level + 1 if success else current_level,
        zeny_cost=cost,
    )


def stat_bonus(item_type: str, level: int) -> dict:
    """Bônus de atributo concedido pelo refinamento."""
    if item_type == "weapon":
        return {"atk": level * 2}
    if item_type in _REFINE_TYPES:
        return {"def": level}
    return {}
