extends Node

var token: String = ""
var player_id: String = ""
var character: Dictionary = {}

# ── Configurações de exibição de log (persistidas) ─────────────────────────────
var log_damage : bool = true   # dano causado/recebido na aba Batalha
var log_xp     : bool = true   # xp ganho/perdido na aba Batalha
var log_drops  : bool = true   # drops pegos (em todas as abas)

const _CFG_PATH := "user://log_settings.cfg"

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CFG_PATH) == OK:
		log_damage = bool(cfg.get_value("log", "damage", true))
		log_xp     = bool(cfg.get_value("log", "xp", true))
		log_drops  = bool(cfg.get_value("log", "drops", true))

func save_log_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("log", "damage", log_damage)
	cfg.set_value("log", "xp", log_xp)
	cfg.set_value("log", "drops", log_drops)
	cfg.save(_CFG_PATH)

func is_logged_in() -> bool:
	return token != ""

func is_character_selected() -> bool:
	return character.has("id") and character["id"] != ""

func clear() -> void:
	token = ""
	player_id = ""
	character = {}
