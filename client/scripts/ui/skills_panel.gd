extends Control

var _pending     : Dictionary = {}  # skill_id → levels pendentes
var _rows        : Dictionary = {}  # skill_id → {cur_lbl, pend_lbl, cur_level, max_level}
var _avail_lbl   : Label
var _apply_btn   : Button
var _list_box    : VBoxContainer
var _panel       : PanelContainer
var _drag_offset : Vector2 = Vector2.ZERO
var _dragging    : bool    = false
var _applying    : int     = 0

func _ready() -> void:
	_build_ui()
	call_deferred("_center_panel")

func _on_visibility_changed() -> void:
	if visible:
		_pending.clear()
		_rows.clear()
		_fetch_skills()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	_panel.add_child(outer)

	# Barra de título arrastável
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 26)
	title_bar.add_theme_constant_override("separation", 4)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_drag)
	outer.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = ":: Habilidades"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(title_lbl)

	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(24, 0)
	x_btn.pressed.connect(_on_close)
	title_bar.add_child(x_btn)

	outer.add_child(HSeparator.new())

	_avail_lbl = Label.new()
	_avail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avail_lbl.add_theme_font_size_override("font_size", 12)
	_avail_lbl.modulate = Color(1.0, 0.9, 0.3)
	_avail_lbl.text = "Carregando..."
	outer.add_child(_avail_lbl)

	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 3)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	outer.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	outer.add_child(btn_row)

	_apply_btn = Button.new()
	_apply_btn.text = "Aplicar"
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn.disabled = true
	_apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(_apply_btn)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)

func _center_panel() -> void:
	var vp := get_viewport()
	if vp == null or _panel == null:
		return
	var s := vp.get_visible_rect().size
	_panel.position = Vector2((s.x - 360.0) * 0.5, (s.y - 440.0) * 0.5)

# ── Dados ─────────────────────────────────────────────────────────────────────

func _fetch_skills() -> void:
	var char_id := str(GameState.character.get("id", ""))
	ApiClient.get_req("/api/characters/%s/skills" % char_id, _on_skills_loaded)

func _on_skills_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		_avail_lbl.text = "Erro ao carregar habilidades."
		return
	_rebuild_rows(data)

func _rebuild_rows(skills: Array) -> void:
	for child in _list_box.get_children():
		child.queue_free()
	_rows.clear()
	_pending.clear()
	for skill in skills:
		_build_skill_row(skill)
	_refresh_avail()

func _build_skill_row(skill: Dictionary) -> void:
	var skill_id : String = skill.get("id", "")
	var name_str : String = skill.get("name", skill_id)
	var cur_lv   : int    = skill.get("current_level", 0)
	var max_lv   : int    = skill.get("max_level", 1)
	var sk_type  : String = skill.get("type", "passive")
	var sp_cost  : int    = skill.get("sp_cost", 0)

	_pending[skill_id] = 0

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	_list_box.add_child(row)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	row.add_child(top)

	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	top.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = "[A]" if sk_type == "active" else "[P]"
	type_lbl.modulate = Color(0.6, 0.9, 1.0) if sk_type == "active" else Color(0.75, 1.0, 0.6)
	type_lbl.add_theme_font_size_override("font_size", 10)
	top.add_child(type_lbl)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(24, 0)
	minus_btn.pressed.connect(_on_minus.bind(skill_id))
	top.add_child(minus_btn)

	var cur_lbl := Label.new()
	cur_lbl.text = "%d/%d" % [cur_lv, max_lv]
	cur_lbl.custom_minimum_size = Vector2(38, 0)
	cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cur_lbl.add_theme_font_size_override("font_size", 11)
	top.add_child(cur_lbl)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(24, 0)
	plus_btn.pressed.connect(_on_plus.bind(skill_id, max_lv))
	top.add_child(plus_btn)

	var pend_lbl := Label.new()
	pend_lbl.text = "+0"
	pend_lbl.custom_minimum_size = Vector2(28, 0)
	pend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pend_lbl.add_theme_font_size_override("font_size", 11)
	pend_lbl.modulate = Color(1.0, 0.9, 0.3)
	top.add_child(pend_lbl)

	if sp_cost > 0:
		var info_lbl := Label.new()
		info_lbl.text = "  SP: %d" % sp_cost
		info_lbl.add_theme_font_size_override("font_size", 10)
		info_lbl.modulate = Color(0.55, 0.55, 0.55)
		row.add_child(info_lbl)

	_list_box.add_child(HSeparator.new())

	_rows[skill_id] = {
		"cur_lbl":   cur_lbl,
		"pend_lbl":  pend_lbl,
		"cur_level": cur_lv,
		"max_level": max_lv,
	}

func _refresh_avail() -> void:
	var used  := _total_pending()
	var avail := CharacterData.skill_points - used
	_avail_lbl.text = "Pontos de habilidade: %d" % avail
	_apply_btn.disabled = used == 0

func _total_pending() -> int:
	var t := 0
	for k in _pending:
		t += _pending[k]
	return t

# ── Controles ─────────────────────────────────────────────────────────────────

func _on_plus(skill_id: String, max_lv: int) -> void:
	var row_data = _rows.get(skill_id)
	if row_data == null:
		return
	var cur_lv : int = row_data["cur_level"]
	var pend   : int = _pending.get(skill_id, 0)
	if cur_lv + pend >= max_lv:
		return
	if _total_pending() >= CharacterData.skill_points:
		return
	_pending[skill_id] = pend + 1
	row_data["pend_lbl"].text = "+%d" % _pending[skill_id]
	row_data["cur_lbl"].text  = "%d/%d" % [cur_lv + _pending[skill_id], max_lv]
	_refresh_avail()

func _on_minus(skill_id: String) -> void:
	if _pending.get(skill_id, 0) <= 0:
		return
	_pending[skill_id] -= 1
	var row_data = _rows.get(skill_id)
	if row_data != null:
		var cur_lv : int = row_data["cur_level"]
		var max_lv : int = row_data["max_level"]
		row_data["pend_lbl"].text = "+%d" % _pending[skill_id]
		row_data["cur_lbl"].text  = "%d/%d" % [cur_lv + _pending[skill_id], max_lv]
	_refresh_avail()

func _on_apply() -> void:
	var to_send : Array = []
	for skill_id in _pending:
		if _pending[skill_id] > 0:
			to_send.append({"skill_id": skill_id, "levels": _pending[skill_id]})
	if to_send.is_empty():
		return
	_apply_btn.disabled = true
	_applying = to_send.size()
	var char_id := str(GameState.character.get("id", ""))
	for entry in to_send:
		ApiClient.post("/api/characters/%s/allocate-skill" % char_id, entry, _on_allocate_resp)

func _on_allocate_resp(code: int, data) -> void:
	_applying -= 1
	if code == 200 and data != null:
		CharacterData.apply_from_response(data)
	if _applying <= 0:
		_pending.clear()
		_rows.clear()
		_fetch_skills()

func _on_close() -> void:
	visible = false

# ── Drag ──────────────────────────────────────────────────────────────────────

func _on_title_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_offset = _panel.position - get_local_mouse_position()

func _input(event: InputEvent) -> void:
	if not visible or not _dragging:
		return
	if event is InputEventMouseMotion:
		_panel.position = get_local_mouse_position() + _drag_offset
	elif event is InputEventMouseButton and not event.pressed:
		_dragging = false
