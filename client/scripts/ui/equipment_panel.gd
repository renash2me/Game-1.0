extends Control

const SLOTS : Array = [
	["head",       "Cabeça"],
	["body",       "Corpo"],
	["legs",       "Pernas"],
	["feet",       "Pés"],
	["weapon",     "Arma"],
	["offhand",    "Escudo"],
	["accessory1", "Acessório 1"],
	["accessory2", "Acessório 2"],
]

var _slot_data   : Dictionary = {}
var _panel       : PanelContainer
var _drag_offset : Vector2 = Vector2.ZERO
var _dragging    : bool    = false
var _resize_grip           = null
var _resizing    : bool    = false
var _res_mouse   : Vector2 = Vector2.ZERO
var _res_size    : Vector2 = Vector2.ZERO

func _ready() -> void:
	_build_ui()
	call_deferred("_center_panel")

func _on_visibility_changed() -> void:
	if visible:
		_fetch_inventory()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # ver inventory_ui: deixa outras janelas/mapa clicáveis

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(290, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 26)
	title_bar.add_theme_constant_override("separation", 4)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_drag)
	vbox.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = ":: Equipamentos"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(title_lbl)

	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(24, 0)
	x_btn.pressed.connect(_on_close)
	title_bar.add_child(x_btn)

	vbox.add_child(HSeparator.new())

	# Área rolável com os slots — permite resize real
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	for slot_def in SLOTS:
		inner.add_child(_build_slot_row(slot_def[0], slot_def[1]))

	vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.pressed.connect(_on_close)
	vbox.add_child(close_btn)

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

func _build_slot_row(slot_name: String, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var slot_lbl := Label.new()
	slot_lbl.text = label + ":"
	slot_lbl.custom_minimum_size = Vector2(88, 0)
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.modulate = Color(0.72, 0.72, 0.72)
	row.add_child(slot_lbl)

	var item_lbl := Label.new()
	item_lbl.text = "(vazio)"
	item_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_lbl.add_theme_font_size_override("font_size", 11)
	item_lbl.modulate = Color(0.45, 0.45, 0.45)
	row.add_child(item_lbl)

	var unequip_btn := Button.new()
	unequip_btn.text = "Tirar"
	unequip_btn.add_theme_font_size_override("font_size", 10)
	unequip_btn.visible = false
	unequip_btn.pressed.connect(_on_unequip.bind(slot_name))
	row.add_child(unequip_btn)

	_slot_data[slot_name] = {"item_lbl": item_lbl, "btn": unequip_btn, "inv_id": ""}
	return row

func _center_panel() -> void:
	var vp := get_viewport()
	if vp == null or _panel == null:
		return
	var s := vp.get_visible_rect().size
	_panel.position = Vector2((s.x - _panel.size.x) * 0.5, (s.y - _panel.size.y) * 0.5)
	_update_grip()

# ── Dados ─────────────────────────────────────────────────────────────────────

func _fetch_inventory() -> void:
	var char_id := str(GameState.character.get("id", ""))
	ApiClient.get_req("/api/inventory/%s" % char_id, _on_inv_loaded)

func _on_inv_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	_refresh_slots(data)

func _refresh_slots(inv: Array) -> void:
	for sname in _slot_data:
		var sd = _slot_data[sname]
		sd["item_lbl"].text     = "(vazio)"
		sd["item_lbl"].modulate = Color(0.45, 0.45, 0.45)
		sd["btn"].visible       = false
		sd["btn"].disabled      = false
		sd["inv_id"]            = ""

	for item in inv:
		if not item.get("is_equipped", false):
			continue
		var sname : String = item.get("equip_slot", "")
		if sname not in _slot_data:
			continue
		var sd = _slot_data[sname]
		sd["item_lbl"].text     = _fmt_item(item.get("item_id", ""), item.get("refinement", 0))
		sd["item_lbl"].modulate = Color(1.0, 1.0, 1.0)
		sd["btn"].visible       = true
		sd["inv_id"]            = str(item.get("id", ""))

func _fmt_item(item_id: String, refinement: int) -> String:
	var parts  := item_id.split("_")
	var result := ""
	for p in parts:
		if p.length() > 0:
			result += p.substr(0, 1).to_upper() + p.substr(1) + " "
	result = result.strip_edges()
	if refinement > 0:
		result += " +%d" % refinement
	return result

# ── Ações ─────────────────────────────────────────────────────────────────────

func _on_unequip(slot_name: String) -> void:
	var sd = _slot_data.get(slot_name)
	if sd == null or sd["inv_id"] == "":
		return
	sd["btn"].disabled = true
	var char_id := str(GameState.character.get("id", ""))
	ApiClient.post(
		"/api/inventory/%s/unequip" % char_id,
		{"inventory_item_id": sd["inv_id"]},
		_on_unequip_resp
	)

func _on_unequip_resp(code: int, _data) -> void:
	if code == 200:
		_fetch_inventory()
	else:
		for sname in _slot_data:
			_slot_data[sname]["btn"].disabled = false

func _on_close() -> void:
	visible = false

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
