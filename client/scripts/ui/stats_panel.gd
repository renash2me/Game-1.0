extends Control

const _STAT_DEFS = [
	["str",  "STR"],
	["agi",  "AGI"],
	["vit",  "VIT"],
	["int_", "INT"],
	["dex",  "DEX"],
	["luk",  "LUK"],
]

var _pending        : Dictionary = {}
var _current_labels : Dictionary = {}
var _pending_labels : Dictionary = {}
var _avail_label    : Label
var _apply_btn      : Button
var _panel          : PanelContainer
var _drag_offset    : Vector2 = Vector2.ZERO
var _dragging       : bool    = false
var _resize_grip              = null
var _resizing       : bool    = false
var _res_mouse      : Vector2 = Vector2.ZERO
var _res_size       : Vector2 = Vector2.ZERO

func _ready() -> void:
	for d in _STAT_DEFS:
		_pending[d[0]] = 0
	_build_ui()
	_refresh()
	call_deferred("_center_panel")

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(260, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Barra de título arrastável
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 26)
	title_bar.add_theme_constant_override("separation", 4)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_drag)
	vbox.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = ":: Atributos"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(title_lbl)

	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(24, 0)
	close_x.pressed.connect(_on_close_pressed)
	title_bar.add_child(close_x)

	vbox.add_child(HSeparator.new())

	_avail_label = Label.new()
	_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avail_label.add_theme_font_size_override("font_size", 12)
	_avail_label.modulate = Color(1.0, 0.9, 0.3)
	vbox.add_child(_avail_label)

	vbox.add_child(HSeparator.new())

	# Área rolável com as stats — permite resize real
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	for d in _STAT_DEFS:
		_build_stat_row(inner, d[0], d[1])

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_apply_btn = Button.new()
	_apply_btn.text = "Aplicar"
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn.pressed.connect(_on_apply_pressed)
	btn_row.add_child(_apply_btn)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(close_btn)

	_setup_resize()
	WindowManager.register(_panel)

func _setup_resize() -> void:
	_resize_grip = ColorRect.new()
	_resize_grip.size = Vector2(12, 12)
	_resize_grip.color = Color(0.55, 0.55, 0.55, 0.65)
	_resize_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_grip.gui_input.connect(_on_grip_input)
	add_child(_resize_grip)
	call_deferred("_update_grip")

func _update_grip() -> void:
	if _resize_grip == null or not is_instance_valid(_resize_grip):
		return
	_resize_grip.position = _panel.position + _panel.size - Vector2(12, 12)

func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if event.pressed:
			_res_mouse = get_local_mouse_position()
			_res_size  = _panel.size

func _exit_tree() -> void:
	WindowManager.unregister(_panel)

func _center_panel() -> void:
	var vp := get_viewport()
	if vp == null or _panel == null:
		return
	var s := vp.get_visible_rect().size
	_panel.position = Vector2(
		(s.x - _panel.size.x) * 0.5,
		(s.y - _panel.size.y) * 0.5
	)
	_update_grip()

func _build_stat_row(parent: Control, key: String, abbr: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = abbr
	name_lbl.custom_minimum_size = Vector2(34, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "1"
	val_lbl.custom_minimum_size = Vector2(36, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 12)
	_current_labels[key] = val_lbl
	row.add_child(val_lbl)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(28, 0)
	minus_btn.pressed.connect(_on_minus.bind(key))
	row.add_child(minus_btn)

	var pending_lbl := Label.new()
	pending_lbl.text = "+0"
	pending_lbl.custom_minimum_size = Vector2(32, 0)
	pending_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pending_lbl.add_theme_font_size_override("font_size", 12)
	pending_lbl.modulate = Color(1.0, 0.9, 0.3)
	_pending_labels[key] = pending_lbl
	row.add_child(pending_lbl)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 0)
	plus_btn.pressed.connect(_on_plus.bind(key))
	row.add_child(plus_btn)

# ── Drag / Resize ─────────────────────────────────────────────────────────────

func _on_title_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_offset = _panel.position - get_local_mouse_position()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _dragging:
		if event is InputEventMouseMotion:
			var raw := get_local_mouse_position() + _drag_offset
			_panel.position = WindowManager.snap_move(_panel, raw)
			_update_grip()
		elif event is InputEventMouseButton and not event.pressed:
			_dragging = false
	if _resizing:
		if event is InputEventMouseMotion:
			var delta := get_local_mouse_position() - _res_mouse
			var min_sz := _panel.custom_minimum_size
			_panel.size = (_res_size + delta).max(min_sz)
			_resize_grip.position = _panel.position + _panel.size - Vector2(12, 12)
		elif event is InputEventMouseButton and not event.pressed:
			_resizing = false
			_panel.size = WindowManager.snap_size(_panel.size, _panel.custom_minimum_size)
			_update_grip()

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _current_labels.is_empty():
		return
	var base_vals := {
		"str":  CharacterData.str_stat,
		"agi":  CharacterData.agi,
		"vit":  CharacterData.vit,
		"int_": CharacterData.int_stat,
		"dex":  CharacterData.dex,
		"luk":  CharacterData.luk,
	}
	for key in base_vals:
		_current_labels[key].text = str(base_vals[key] + _pending.get(key, 0))
		var p: int = _pending.get(key, 0)
		_pending_labels[key].text = "+%d" % p

	var used  := _total_pending()
	var avail := CharacterData.stat_points - used
	_avail_label.text = "Pontos disponíveis: %d" % avail
	_apply_btn.disabled = used == 0

func _total_pending() -> int:
	var t := 0
	for k in _pending:
		t += _pending[k]
	return t

func _on_plus(key: String) -> void:
	if _total_pending() >= CharacterData.stat_points:
		return
	_pending[key] = _pending.get(key, 0) + 1
	_refresh()

func _on_minus(key: String) -> void:
	if _pending.get(key, 0) <= 0:
		return
	_pending[key] -= 1
	_refresh()

func _on_close_pressed() -> void:
	visible = false

func _on_apply_pressed() -> void:
	if _total_pending() == 0:
		return
	var char_id := str(GameState.character.get("id", ""))
	var body    := {}
	for key in _pending:
		if _pending[key] > 0:
			body[key] = _pending[key]
	_apply_btn.disabled = true
	ApiClient.post("/api/characters/%s/allocate-stats" % char_id, body, _on_allocate_response)

func _on_allocate_response(code: int, data) -> void:
	if code == 200 and data != null:
		CharacterData.apply_from_response(data)
		for k in _pending:
			_pending[k] = 0
		_refresh()
	else:
		_apply_btn.disabled = false
