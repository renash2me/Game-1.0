extends CanvasLayer

@onready var _hp_bar     : ProgressBar = $Panel/VBox/HP/Bar
@onready var _hp_lbl     : Label       = $Panel/VBox/HP/Label
@onready var _sp_bar     : ProgressBar = $Panel/VBox/SP/Bar
@onready var _sp_lbl     : Label       = $Panel/VBox/SP/Label
@onready var _xp_bar     : ProgressBar = $Panel/VBox/XP/Bar
@onready var _xp_lbl     : Label       = $Panel/VBox/XP/Label
@onready var _level_lbl  : Label       = $Panel/VBox/Level
@onready var _zeny_lbl   : Label       = $Panel/VBox/Zeny
@onready var _class_lbl  : Label       = $Panel/VBox/ClassRow/ClassLbl
@onready var _stat_badge : Label       = $Panel/VBox/ClassRow/StatBadge
@onready var _notif_lbl  : Label       = $Notification

var _stats_panel
var _class_panel

func _ready() -> void:
	CharacterData.hp_changed.connect(_refresh_hp)
	CharacterData.sp_changed.connect(_refresh_sp)
	CharacterData.xp_changed.connect(_refresh_xp)
	CharacterData.level_changed.connect(_on_level_changed)
	CharacterData.zeny_changed.connect(_refresh_zeny)
	CharacterData.stats_changed.connect(_refresh_class_row)
	CharacterData.class_changed.connect(_on_class_changed)

	_refresh_hp(CharacterData.hp, CharacterData.max_hp)
	_refresh_sp(CharacterData.sp, CharacterData.max_sp)
	_refresh_xp(CharacterData.xp, CharacterData.xp_to_next)
	_refresh_level(CharacterData.level)
	_refresh_zeny(CharacterData.zeny)
	_refresh_class_row()

	_notif_lbl.text = ""
	_notif_lbl.modulate.a = 0.0

	_stats_panel = load("res://scripts/ui/stats_panel.gd").new()
	add_child(_stats_panel)
	_stats_panel.visible = false

	_class_panel = load("res://scripts/ui/class_change.gd").new()
	add_child(_class_panel)
	_class_panel.visible = false
	_class_panel.class_chosen.connect(_on_class_panel_chosen)
	_class_panel.dismissed.connect(_on_class_panel_dismissed)

	_check_class_change_available()

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
	var pct := int(float(xp) / float(max(xp_next, 1)) * 100.0)
	_xp_lbl.text = "%d%%" % pct

func _refresh_level(level: int) -> void:
	_level_lbl.text = "Lv. %d" % level

func _refresh_zeny(zeny: int) -> void:
	_zeny_lbl.text = "z %d" % zeny

func _refresh_class_row() -> void:
	var cname := CharacterData.class_id.replace("_", " ").capitalize()
	_class_lbl.text = "(%s)" % cname
	var pts := CharacterData.stat_points
	_stat_badge.visible = pts > 0
	_stat_badge.text = "%d pts" % pts

# ── Notificação flutuante ─────────────────────────────────────────────────────

func show_notification(text: String, color: Color = Color.YELLOW) -> void:
	_notif_lbl.text = text
	_notif_lbl.modulate = color
	_notif_lbl.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(_notif_lbl, "modulate:a", 0.0, 0.8)

# ── Painel de atributos ────────────────────────────────────────────────────────

func _on_stats_btn_pressed() -> void:
	if _class_panel.visible:
		return
	_stats_panel.visible = !_stats_panel.visible
	if _stats_panel.visible:
		_stats_panel.call("_refresh")

# ── Troca de classe ────────────────────────────────────────────────────────────

func _check_class_change_available() -> void:
	if CharacterData.class_id == "novice" and CharacterData.level >= 25:
		_class_panel.visible = true

func _on_level_changed(level: int) -> void:
	_refresh_level(level)
	_check_class_change_available()

func _on_class_changed(_new_class_id: String) -> void:
	_refresh_class_row()

func _on_class_panel_chosen(_id: String) -> void:
	show_notification("Classe escolhida! Bem-vindo, aventureiro!")

func _on_class_panel_dismissed() -> void:
	show_notification("Abra o painel de Atributos (C) para trocar de classe.", Color.WHITE)

# ── Atalho de teclado ─────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			_on_stats_btn_pressed()
			get_viewport().set_input_as_handled()
