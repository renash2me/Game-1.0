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
var _skills_panel
var _equip_panel

# ── Drag / Resize do HUD ──────────────────────────────────────────────────────
var _hud_dragging      : bool    = false
var _hud_drag_offset   : Vector2 = Vector2.ZERO
var _hud_resizing      : bool    = false
var _hud_resize_origin : Vector2 = Vector2.ZERO
var _hud_resize_base   : float   = 1.0
var _hud_grip                    # ColorRect — não tipado para evitar problemas 4.7

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

	_skills_panel = load("res://scripts/ui/skills_panel.gd").new()
	add_child(_skills_panel)
	_skills_panel.visible = false

	_equip_panel = load("res://scripts/ui/equipment_panel.gd").new()
	add_child(_equip_panel)
	_equip_panel.visible = false

	_check_class_change_available()
	_setup_hud_drag()

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

# ── Painéis de Skills e Equipamentos ─────────────────────────────────────────

func _on_skills_btn_pressed() -> void:
	if _class_panel.visible:
		return
	_skills_panel.visible = !_skills_panel.visible

func _on_equip_btn_pressed() -> void:
	_equip_panel.visible = !_equip_panel.visible

# ── Atalho de teclado ─────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_on_stats_btn_pressed()
				get_viewport().set_input_as_handled()
			KEY_K:
				_on_skills_btn_pressed()
				get_viewport().set_input_as_handled()
			KEY_E:
				_on_equip_btn_pressed()
				get_viewport().set_input_as_handled()

# ── Drag / Resize ─────────────────────────────────────────────────────────────

func _setup_hud_drag() -> void:
	var panel := $Panel
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)

	# Barra de arraste no topo do VBox
	var handle := Label.new()
	handle.text = ":: HUD"
	handle.add_theme_font_size_override("font_size", 10)
	handle.modulate = Color(0.6, 0.6, 0.6)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.custom_minimum_size = Vector2(0, 14)
	handle.gui_input.connect(_on_hud_handle_input)
	$Panel/VBox.add_child(handle)
	$Panel/VBox.move_child(handle, 0)

	# Botões Skills e Equip
	var extra_row := HBoxContainer.new()
	extra_row.add_theme_constant_override("separation", 4)
	$Panel/VBox.add_child(extra_row)

	var skills_btn := Button.new()
	skills_btn.text = "Skills (K)"
	skills_btn.add_theme_font_size_override("font_size", 10)
	skills_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_btn.pressed.connect(_on_skills_btn_pressed)
	extra_row.add_child(skills_btn)

	var equip_btn := Button.new()
	equip_btn.text = "Equip (E)"
	equip_btn.add_theme_font_size_override("font_size", 10)
	equip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_btn.pressed.connect(_on_equip_btn_pressed)
	extra_row.add_child(equip_btn)

	# Grip de resize no canto inferior direito (filho direto do CanvasLayer)
	_hud_grip = ColorRect.new()
	_hud_grip.color = Color(0.55, 0.55, 0.55, 0.5)
	_hud_grip.size = Vector2(10, 10)
	_hud_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_hud_grip.gui_input.connect(_on_hud_grip_input)
	add_child(_hud_grip)
	call_deferred("_update_hud_grip")

func _update_hud_grip() -> void:
	if _hud_grip == null:
		return
	var panel := $Panel
	var vsize : Vector2 = panel.size * panel.scale
	_hud_grip.position = panel.position + vsize - Vector2(10, 10)

func _hud_mouse() -> Vector2:
	return get_viewport().get_mouse_position()

func _on_hud_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hud_dragging = event.pressed
		if event.pressed:
			_hud_drag_offset = $Panel.position - _hud_mouse()

func _on_hud_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hud_resizing = event.pressed
		if event.pressed:
			_hud_resize_origin = _hud_mouse()
			_hud_resize_base   = $Panel.scale.x

func _input(event: InputEvent) -> void:
	if _hud_dragging:
		if event is InputEventMouseMotion:
			$Panel.position = _hud_mouse() + _hud_drag_offset
			_update_hud_grip()
		elif event is InputEventMouseButton and not event.pressed:
			_hud_dragging = false
	if _hud_resizing:
		if event is InputEventMouseMotion:
			var dx : float = (_hud_mouse().x - _hud_resize_origin.x) * 0.006
			var ns : float = clamp(_hud_resize_base + dx, 0.5, 2.5)
			$Panel.scale = Vector2(ns, ns)
			_update_hud_grip()
		elif event is InputEventMouseButton and not event.pressed:
			_hud_resizing = false
