import random
from dataclasses import dataclass


@dataclass(frozen=True)
class CombatStats:
    atk: int
    def_: int
    hit: int
    flee: int
    crit: int  # em unidades de 1/10000 — ex: 500 = 5%


def stats_from_character(char: dict) -> CombatStats:
    """
    Calcula CombatStats a partir de um dict de atributos do personagem.
    `char` pode vir de um ORM model serializado ou de cache Redis.
    """
    level = int(char.get("level", 1))
    str_val = int(char.get("str_stat", 1))
    agi = int(char.get("agi", 1))
    vit = int(char.get("vit", 1))
    dex = int(char.get("dex", 1))
    luk = int(char.get("luk", 1))

    atk = str_val + (str_val // 10) ** 2  # bônus STR quadrático como no RO
    return CombatStats(
        atk=atk,
        def_=vit // 2,
        hit=dex + level,
        flee=agi + level,
        crit=luk * 30,  # 30/10000 por LUK = 0.3% por ponto
    )


def stats_from_mob(mob: dict) -> CombatStats:
    """Calcula CombatStats de uma instância de mob."""
    level = int(mob.get("level", 1))
    atk = random.randint(
        int(mob.get("attack_min", 5)),
        int(mob.get("attack_max", 10)),
    )
    return CombatStats(
        atk=atk,
        def_=int(mob.get("defense", 0)),
        hit=int(mob.get("dex", 6)) + level,
        flee=int(mob.get("agi", 1)) + level,
        crit=int(mob.get("luk", 5)) * 30,
    )


def physical_attack(attacker: CombatStats, defender: CombatStats) -> tuple[int, bool, bool]:
    """
    Calcula um ataque físico.
    Retorna: (damage, is_miss, is_critical)
    """
    # Chance de miss: diferença entre flee do defensor e hit do atacante
    miss_chance = max(0.05, min(0.95, (defender.flee - attacker.hit) / 200 + 0.2))
    if random.random() < miss_chance:
        return 0, True, False

    # Crítico
    is_crit = random.randint(1, 10_000) <= attacker.crit

    # Dano base com ±10% de aleatoriedade
    base = attacker.atk * random.uniform(0.9, 1.1)

    if is_crit:
        damage = int(base * 1.5)
    else:
        reduction = max(0.0, min(0.9, defender.def_ / 100))
        damage = int(base * (1.0 - reduction))

    return max(1, damage), False, is_crit
