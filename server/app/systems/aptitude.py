"""
Sistema de aptidão silenciosa.

Rastreia comportamentos do jogador sem exibir ao jogador. Os dados
acumulados determinam elegibilidade a classes secretas e supremas.
Ativo para todos os personagens com class_tier < 4.
"""

_VOID_KILL_EXPOSURE = 5   # pontos de void_exposure por kill de mob void
_VOID_MAP_EXPOSURE  = 1   # pontos por visita a mapa void


def record_kill(data: dict) -> dict:
    d = dict(data)
    d["combat_kills"] = d.get("combat_kills", 0) + 1
    return d


def record_kill_melee(data: dict) -> dict:
    d = dict(data)
    d["melee_kills"] = d.get("melee_kills", 0) + 1
    return d


def record_kill_ranged(data: dict) -> dict:
    d = dict(data)
    d["ranged_kills"] = d.get("ranged_kills", 0) + 1
    return d


def record_void_kill(data: dict) -> dict:
    d = dict(data)
    d["void_exposure"] = d.get("void_exposure", 0) + _VOID_KILL_EXPOSURE
    return d


def record_void_map(data: dict) -> dict:
    d = dict(data)
    d["void_exposure"] = d.get("void_exposure", 0) + _VOID_MAP_EXPOSURE
    return d


def record_damage_dealt(data: dict, amount: int) -> dict:
    d = dict(data)
    d["damage_dealt"] = d.get("damage_dealt", 0) + amount
    return d


def record_damage_taken(data: dict, amount: int) -> dict:
    d = dict(data)
    d["damage_taken"] = d.get("damage_taken", 0) + amount
    return d


def record_map_visit(data: dict, map_id: str) -> dict:
    d = dict(data)
    explored: list = list(d.get("maps_explored", []))
    if map_id not in explored:
        explored.append(map_id)
    d["maps_explored"] = explored
    return d


def record_zeny_looted(data: dict, amount: int) -> dict:
    d = dict(data)
    d["zeny_looted"] = d.get("zeny_looted", 0) + amount
    return d


def record_ally_healed(data: dict, amount: int) -> dict:
    d = dict(data)
    d["allies_healed"] = d.get("allies_healed", 0) + amount
    return d


def apply_kill_aptitude(data: dict, mob_data: dict, attack_type: str, damage: int) -> dict:
    """
    Aplica todas as métricas de aptidão relevantes por kill.
    Ponto de entrada único para o handler de morte de mob.
    """
    d = record_kill(data)
    d = record_damage_dealt(d, damage)

    if attack_type == "ranged":
        d = record_kill_ranged(d)
    else:
        d = record_kill_melee(d)

    if "void" in mob_data.get("tags", []):
        d = record_void_kill(d)

    return d
