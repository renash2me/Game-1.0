import random
from dataclasses import dataclass


@dataclass(frozen=True)
class CombatStats:
    atk: int
    def_: int
    hit: int
    flee: int
    crit: float          # em PORCENTAGEM — ex: 10.0 = 10%
    perfect_dodge: float = 0.0  # % de esquiva garantida (ignora hit)


def stats_from_character(char: dict) -> CombatStats:
    """
    Calcula CombatStats a partir de um dict de atributos do personagem,
    usando as fórmulas configuráveis (data/formulas.json, editáveis no admin).
    `char` pode vir de um ORM model serializado ou de cache Redis.
    """
    from app.systems.formulas import derive_stats

    d = derive_stats(
        level=int(char.get("level", 1)),
        str_=int(char.get("str_stat", 1)),
        agi=int(char.get("agi", 1)),
        vit=int(char.get("vit", 1)),
        int_=int(char.get("int_stat", 1)),
        dex=int(char.get("dex", 1)),
        luk=int(char.get("luk", 1)),
    )
    return CombatStats(
        atk=int(d.get("atk", 1)),
        def_=int(d.get("def", 0)),
        hit=int(d.get("hit", 1)),
        flee=int(d.get("flee", 1)),
        crit=float(d.get("crit", 0.0)),
        perfect_dodge=float(d.get("perfect_dodge", 0.0)),
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
        crit=int(mob.get("luk", 5)) * 0.3 + 1.0,  # mesma escala % do personagem
        perfect_dodge=0.0,
    )


def physical_attack(attacker: CombatStats, defender: CombatStats) -> tuple[int, bool, bool]:
    """
    Calcula um ataque físico.
    Retorna: (damage, is_miss, is_critical)
    """
    # Perfect Dodge: esquiva garantida (% do defensor, ignora hit)
    if defender.perfect_dodge > 0 and random.uniform(0, 100) < defender.perfect_dodge:
        return 0, True, False

    # Chance de miss: diferença entre flee do defensor e hit do atacante
    miss_chance = max(0.05, min(0.95, (defender.flee - attacker.hit) / 200 + 0.2))
    if random.random() < miss_chance:
        return 0, True, False

    # Crítico (crit em porcentagem)
    is_crit = random.uniform(0, 100) < attacker.crit

    # Dano base com ±10% de aleatoriedade
    base = attacker.atk * random.uniform(0.9, 1.1)

    if is_crit:
        damage = int(base * 1.5)
    else:
        reduction = max(0.0, min(0.9, defender.def_ / 100))
        damage = int(base * (1.0 - reduction))

    return max(1, damage), False, is_crit
