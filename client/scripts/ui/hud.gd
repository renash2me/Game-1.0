extends CanvasLayer

@onready var _hp_bar    : ProgressBar = $Panel/VBox/HP/Bar
@onready var _hp_lbl    : Label       = $Panel/VBox/HP/Label
@onready var _sp_bar    : ProgressBar = $Panel/VBox/SP/Bar
@onready var _sp_lbl    : Label       = $Panel/VBox/SP/Label
@onready var _xp_bar    : ProgressBar = $Panel/VBox/XP/Bar
@onready var _xp_lbl    : Label       = $Panel/VBox/XP/Label
@onready var _level_lbl : Label       = $Panel/VBox/Level
@onready var _zeny_lbl  : Label       = $Panel/VBox/Zeny
@onready var _notif_lbl : Label       = $Notification

func _ready() -> void:
	CharacterData.hp_changed.connect(_refresh_hp)
	CharacterData.sp_changed.connect(_refresh_sp)
	CharacterData.xp_changed.connect(_refresh_xp)
	CharacterData.level_changed.connect(_refresh_level)
	CharacterData.zeny_changed.connect(_refresh_zeny)

	_refresh_hp(CharacterData.hp, CharacterData.max_hp)
	_refresh_sp(CharacterData.sp, CharacterData.max_sp)
	_refresh_xp(CharacterData.xp, CharacterData.xp_to_next)
	_refresh_level(CharacterData.level)
	_refresh_zeny(CharacterData.zeny)

	_notif_lbl.text = ""
	_notif_lbl.modulate.a = 0.0

# ── Refreshes ─────────────────────────────────────────────────────────────────

func _refresh_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max(max_hp, 1)
	_hp_bar.value = hp
	_hp_lbl.text = "%d / %d" % [hp, max_hp]

func _refresh_sp(sp: int, max_sp: int) -> void:
	_sp_bar.max_value = max(max_sp, 1)
	_sp_bar.value = sp
	_sp_lbl.text = "%d / %d" % [sp, max_sp]

func _refresh_xp(xp: int, xp_next: int) -> void:
	_xp_bar.max_value = max(xp_next, 1)
	_xp_bar.value = xp
	_xp_lbl.text = "%d / %d xp" % [xp, xp_next]

func _refresh_level(level: int) -> void:
	_level_lbl.text = "Lv. %d" % level

func _refresh_zeny(zeny: int) -> void:
	_zeny_lbl.text = "z %d" % zeny

# ── Notificação flutuante ─────────────────────────────────────────────────────

func show_notification(text: String, color: Color = Color.YELLOW) -> void:
	_notif_lbl.text = text
	_notif_lbl.modulate = color
	_notif_lbl.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_notif_lbl, "modulate:a", 0.0, 0.8)
