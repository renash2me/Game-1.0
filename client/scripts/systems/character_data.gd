extends Node

signal hp_changed(current: int, maximum: int)
signal sp_changed(current: int, maximum: int)
signal xp_changed(current: int, to_next: int)
signal level_changed(new_level: int)
signal zeny_changed(amount: int)

# Propriedades locais — inicializadas quando o personagem é carregado
var hp       : int = 0
var max_hp   : int = 1
var sp       : int = 0
var max_sp   : int = 1
var xp       : int = 0
var xp_to_next : int = 1
var level    : int = 1
var zeny     : int = 0

func init_from_character(char: Dictionary) -> void:
	hp       = char.get("hp", 100)
	max_hp   = char.get("max_hp", 100)
	sp       = char.get("sp", 50)
	max_sp   = char.get("max_sp", 50)
	xp       = char.get("xp", 0)
	xp_to_next = char.get("xp_to_next", 10)
	level    = char.get("level", 1)
	zeny     = char.get("zeny", 0)

func apply_damage(new_hp: int, new_max_hp: int) -> void:
	hp     = new_hp
	max_hp = new_max_hp
	GameState.character["hp"] = new_hp
	hp_changed.emit(hp, max_hp)

func apply_sp(new_sp: int, new_max_sp: int) -> void:
	sp     = new_sp
	max_sp = new_max_sp
	GameState.character["sp"] = new_sp
	sp_changed.emit(sp, max_sp)

func apply_xp(new_xp: int, new_xp_to_next: int) -> void:
	xp       = new_xp
	xp_to_next = new_xp_to_next
	GameState.character["xp"]       = new_xp
	GameState.character["xp_to_next"] = new_xp_to_next
	xp_changed.emit(xp, xp_to_next)

func apply_level_up(new_level: int, stat_pts: int, skill_pts: int) -> void:
	level = new_level
	GameState.character["level"]       = new_level
	GameState.character["stat_points"]  = stat_pts
	GameState.character["skill_points"] = skill_pts
	level_changed.emit(level)

func apply_zeny(new_zeny: int) -> void:
	zeny = new_zeny
	GameState.character["zeny"] = new_zeny
	zeny_changed.emit(zeny)
