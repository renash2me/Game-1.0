extends Node

signal hp_changed(current: int, maximum: int)
signal sp_changed(current: int, maximum: int)
signal xp_changed(current: int, to_next: int)
signal level_changed(new_level: int)
signal zeny_changed(amount: int)
signal stats_changed()
signal class_changed(new_class_id: String)

var hp:          int = 0
var max_hp:      int = 1
var sp:          int = 0
var max_sp:      int = 1
var xp:          int = 0
var xp_to_next:  int = 1
var level:       int = 1
var zeny:        int = 0

var str_stat:    int = 1
var agi:         int = 1
var vit:         int = 1
var int_stat:    int = 1
var dex:         int = 1
var luk:         int = 1
var stat_points: int = 0
var skill_points: int = 0

var class_id:   String = "novice"
var class_tier: int    = 0
var char_name:  String = ""

func init_from_character(char: Dictionary) -> void:
	char_name    = char.get("name", "")
	class_id     = char.get("class_id", "novice")
	class_tier   = char.get("class_tier", 0)
	level        = char.get("level", 1)
	xp           = char.get("xp", 0)
	xp_to_next   = char.get("xp_to_next", 10)
	hp           = char.get("hp", 100)
	max_hp       = char.get("hp_max", 100)
	sp           = char.get("sp", 50)
	max_sp       = char.get("sp_max", 50)
	zeny         = char.get("zeny", 0)
	str_stat     = char.get("str_stat", 1)
	agi          = char.get("agi", 1)
	vit          = char.get("vit", 1)
	int_stat     = char.get("int_stat", 1)
	dex          = char.get("dex", 1)
	luk          = char.get("luk", 1)
	stat_points  = char.get("stat_points", 0)
	skill_points = char.get("skill_points", 0)

func apply_from_response(char: Dictionary) -> void:
	var old_class := class_id
	init_from_character(char)
	GameState.character = char
	hp_changed.emit(hp, max_hp)
	sp_changed.emit(sp, max_sp)
	xp_changed.emit(xp, xp_to_next)
	level_changed.emit(level)
	zeny_changed.emit(zeny)
	stats_changed.emit()
	if class_id != old_class:
		class_changed.emit(class_id)

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
	xp         = new_xp
	xp_to_next = new_xp_to_next
	GameState.character["xp"]         = new_xp
	GameState.character["xp_to_next"] = new_xp_to_next
	xp_changed.emit(xp, xp_to_next)

func apply_level_up(new_level: int, stat_pts_gained: int, skill_pts_gained: int) -> void:
	level        = new_level
	stat_points  += stat_pts_gained
	skill_points += skill_pts_gained
	GameState.character["level"]        = new_level
	GameState.character["stat_points"]  = stat_points
	GameState.character["skill_points"] = skill_points
	level_changed.emit(level)
	stats_changed.emit()

func apply_zeny(new_zeny: int) -> void:
	zeny = new_zeny
	GameState.character["zeny"] = new_zeny
	zeny_changed.emit(zeny)
