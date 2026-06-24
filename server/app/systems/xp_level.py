LEVEL_CAP = 99
STAT_POINTS_PER_LEVEL = 3
SKILL_POINTS_PER_LEVEL = 1


def xp_for_level(level: int) -> int:
    """XP necessário para avançar do `level` atual para o próximo."""
    if level >= LEVEL_CAP:
        return 0
    return int(10 * (level ** 1.6))


def check_level_up(
    current_level: int,
    current_xp: int,
    current_xp_to_next: int,
) -> tuple[int, int, int, int, int]:
    """
    Processa ganho de XP e retorna o novo estado.
    Retorna: (novo_level, novo_xp, novo_xp_to_next, stat_points, skill_points)
    Pode subir múltiplos levels de uma só vez.
    """
    level = current_level
    xp = current_xp
    stat_points = 0
    skill_points = 0

    while level < LEVEL_CAP:
        needed = xp_for_level(level)
        if xp >= needed:
            xp -= needed
            level += 1
            stat_points += STAT_POINTS_PER_LEVEL
            skill_points += SKILL_POINTS_PER_LEVEL
        else:
            break

    return level, xp, xp_for_level(level), stat_points, skill_points
