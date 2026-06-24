"""
Sistema de aptidão silenciosa — exclusivo do Novice.

Rastreia comportamentos sem exibir ao jogador. Os dados acumulados serão
usados futuramente para determinar elegibilidade a classes secretas.
"""


def record_kill(data: dict) -> dict:
    d = dict(data)
    d["combat_kills"] = d.get("combat_kills", 0) + 1
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
