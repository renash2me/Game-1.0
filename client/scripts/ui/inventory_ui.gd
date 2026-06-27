extends Control

const TABS : Array = [
	["Todos",        ["*"]],
	["Consumíveis",  ["consumable", "zeny_bag"]],
	["Equipamentos", ["weapon", "armor"]],
	["Etc",          []],
]

var _all_items      : Array      = []
var _catalog        : Dictionary = {}
var _catalog_loaded : bool       = false
var _active_tab     : int        = 0
var _tab_btns       : Array      = []
var _list_box       : VBoxContainer
var _detail_box     : VBoxContainer
var _detail_name    : Label
var _detail_info    : Label
var _detail_err     : Label
var _selected_item  : Dictionary = {}
var _panel          : PanelContainer
var _drag_offset    : Vector2    = Vector2.ZERO
var _dragging       : bool       = false
var _char_id        : String     = ""
var _resize_grip                 = null
var _resizing       : bool       = false
var _res_mouse      : Vector2    = Vector2.ZERO
var _res_size       : Vector2    = Vector2.ZERO
var _tooltip                     = null

func _ready() -> void:
	_char_id = str(GameState.character.get("id", ""))
	_build_ui()
	call_deferred("_default_position")
	WsClient.message_received.connect(_on_ws_message)
	visibility_changed.connect(_on_visibility_changed)   # sem isto, abrir não carregava nada

func _on_visibility_changed() -> void:
	if visible:
		_load_data()
	else:
		_hide_detail()

# ── Carregamento ──────────────────────────────────────────────────────────────

func _load_data() -> void:
	if not _catalog_loaded:
		ApiClient.get_req("/api/items", _on_catalog_loaded)
	else:
		_load_inventory()

func _on_catalog_loaded(code: int, data) -> void:
	if code == 200 and data != null:
		for entry in data:
			_catalog[entry.get("id", "")] = entry
		_catalog_loaded = true
	_load_inventory()

func _load_inventory() -> void:
	ApiClient.get_req("/api/inventory/%s" % _char_id, _on_inv_loaded)

func _on_inv_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	_all_items = data
	_hide_detail()
	_render_list()

func _on_ws_message(type: String, payload: Dictionary) -> void:
	if not visible:
		return
	# Atualiza o inventário ao pegar um item (DROP_PICKED) ou subir de nível
	if type == "DROP_PICKED" and str(payload.get("picker_id", "")) == _char_id:
		_load_inventory()
	elif type == "LEVEL_UP":
		_load_inventory()

# ── Construção da UI ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(300, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # consome cliques (não "vaza" pro mapa)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
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
	title_lbl.text = ":: Inventário"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(title_lbl)

	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(24, 0)
	x_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(x_btn)

	vbox.add_child(HSeparator.new())

	# Abas
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	vbox.add_child(tab_row)

	for i in range(TABS.size()):
		var tab_label : String = TABS[i][0]
		var btn := Button.new()
		btn.text = tab_label
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_switch_tab.bind(i))
		tab_row.add_child(btn)
		_tab_btns.append(btn)

	_highlight_tab(0)
	vbox.add_child(HSeparator.new())

	# Lista de itens — área rolável
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	vbox.add_child(HSeparator.new())

	# Detalhe do item selecionado
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 4)
	_detail_box.visible = false
	vbox.add_child(_detail_box)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 13)
	_detail_box.add_child(_detail_name)

	_detail_info = Label.new()
	_detail_info.add_theme_font_size_override("font_size", 11)
	_detail_info.modulate = Color(0.8, 0.8, 0.8)
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_detail_info)

	_detail_err = Label.new()
	_detail_err.add_theme_font_size_override("font_size", 11)
	_detail_err.modulate = Color(1, 0.35, 0.35)
	_detail_err.text = ""
	_detail_box.add_child(_detail_err)

	var drop_btn := Button.new()
	drop_btn.text = "Largar 1 no chão"
	drop_btn.modulate = Color(1.0, 0.8, 0.6)
	drop_btn.pressed.connect(_on_drop_item)
	_detail_box.add_child(drop_btn)

	var close_detail := Button.new()
	close_detail.text = "Fechar detalhe"
	close_detail.pressed.connect(_hide_detail)
	_detail_box.add_child(close_detail)

	vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Fechar Inventário (I)"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func(): visible = false)
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

func _default_position() -> void:
	var vp := get_viewport()
	if vp == null or _panel == null:
		return
	var s := vp.get_visible_rect().size
	_panel.position = Vector2(s.x - _panel.size.x - 10.0, 40.0)
	_update_grip()

# ── Abas ──────────────────────────────────────────────────────────────────────

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	_highlight_tab(idx)
	_hide_detail()
	_render_list()

func _highlight_tab(idx: int) -> void:
	for i in range(_tab_btns.size()):
		_tab_btns[i].modulate = Color(1.0, 1.0, 1.0) if i == idx else Color(0.55, 0.55, 0.55)

# ── Renderização ──────────────────────────────────────────────────────────────

func _render_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()

	var included_types : Array = TABS[_active_tab][1]
	var all_tab_types  : Array = ["consumable", "zeny_bag", "weapon", "armor"]
	var is_all         : bool  = "*" in included_types
	var is_catch_all   : bool  = included_types.is_empty()

	for item in _all_items:
		if item.get("is_equipped", false):
			continue
		var item_id   : String     = item.get("item_id", "")
		var item_cat  : Dictionary = _catalog.get(item_id, {})
		var item_type : String     = item_cat.get("type", "")

		var matches := false
		if is_all:
			matches = true
		elif is_catch_all:
			matches = item_type not in all_tab_types
		else:
			matches = item_type in included_types

		if matches:
			_list_box.add_child(_build_item_row(item, item_cat))

	if _list_box.get_child_count() == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Nenhum item nesta aba."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		_list_box.add_child(empty_lbl)

func _build_item_row(item: Dictionary, cat: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 26)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_gui_input.bind(item, cat))

	var name_str : String = cat.get("name", item.get("item_id", "?"))
	var qty      : int    = item.get("quantity", 1)
	var refine   : int    = item.get("refinement", 0)

	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 10)
	badge.custom_minimum_size = Vector2(36, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if refine > 0:
		badge.text = "+%d" % refine
		badge.modulate = Color(1.0, 0.85, 0.3)
	elif qty > 1:
		badge.text = "x%d" % qty
		badge.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(badge)

	# Indicador visual para itens equipáveis
	if cat.get("equip_slot", "") != "":
		var hint := Label.new()
		hint.text = "2×"
		hint.add_theme_font_size_override("font_size", 9)
		hint.modulate = Color(0.5, 0.8, 1.0, 0.7)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hint)

	return row

func _on_row_gui_input(event: InputEvent, item: Dictionary, cat: Dictionary) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.double_click:
				_do_use_or_equip(item, cat)
			else:
				_select_item(item, cat)
		MOUSE_BUTTON_RIGHT:
			_show_item_tooltip(item, cat)

func _show_item_tooltip(item: Dictionary, cat: Dictionary) -> void:
	if _tooltip == null or not is_instance_valid(_tooltip):
		_tooltip = load("res://scripts/ui/item_tooltip.gd").new()
		_tooltip.visible = false
		add_child(_tooltip)
	var mouse := get_local_mouse_position()
	_tooltip.show_item(item, cat, mouse + Vector2(16, 16))

# ── Detalhe ───────────────────────────────────────────────────────────────────

func _select_item(item: Dictionary, cat: Dictionary) -> void:
	_selected_item = item
	_detail_err.text = ""

	var name_str : String = cat.get("name", item.get("item_id", "?"))
	var refine   : int    = item.get("refinement", 0)
	_detail_name.text = name_str + (" +%d" % refine if refine > 0 else "")
	_detail_info.text = _build_item_desc(item, cat)
	_detail_box.visible = true

func _build_item_desc(item: Dictionary, cat: Dictionary) -> String:
	var lines : Array = []

	var qty : int = item.get("quantity", 1)
	if qty > 1:
		lines.append("Quantidade: %d" % qty)

	match cat.get("type", ""):
		"weapon":
			var atk  : int = cat.get("atk", 0)
			var matk : int = cat.get("matk", 0)
			var slots: int = cat.get("slots", 0)
			if atk  > 0: lines.append("ATK: %d" % atk)
			if matk > 0: lines.append("MATK: %d" % matk)
			if slots > 0: lines.append("Slots: %d" % slots)
		"armor":
			var def  : int = cat.get("def", 0)
			var slots: int = cat.get("slots", 0)
			if def   > 0: lines.append("DEF: %d" % def)
			if slots > 0: lines.append("Slots: %d" % slots)
		"consumable":
			var effect : Dictionary = cat.get("effect", {})
			if effect.has("hp_restore"): lines.append("Restaura %d HP" % effect["hp_restore"])
			if effect.has("sp_restore"): lines.append("Restaura %d SP" % effect["sp_restore"])
		"zeny_bag":
			lines.append("Contém %d zeny" % cat.get("zeny_amount", 0))
		"card":
			var effect : Dictionary = cat.get("effect", {})
			for stat in effect:
				lines.append("%s +%d" % [stat.to_upper(), effect[stat]])

	var cards : Array = item.get("cards", [])
	if not cards.is_empty():
		lines.append("Cartas: " + ", ".join(cards))

	var weight : int = cat.get("weight", 0)
	if weight > 0:
		lines.append("Peso: %.1f" % (weight / 10.0))

	if cat.get("equip_slot", "") != "":
		lines.append("— duplo-clique para equipar —")

	return "\n".join(lines)

func _hide_detail() -> void:
	_selected_item = {}
	_detail_box.visible = false
	_detail_err.text = ""

# ── Largar item no chão ───────────────────────────────────────────────────────

func _on_drop_item() -> void:
	var inv_id : String = str(_selected_item.get("id", ""))
	if inv_id == "":
		return
	WsClient.send({"type": "DROP_ITEM", "payload": {"inventory_item_id": inv_id, "quantity": 1}})
	_hide_detail()
	await get_tree().create_timer(0.3).timeout   # aguarda o servidor remover do inventário
	_load_inventory()

# ── Duplo clique: usar (consumível) ou equipar (equipamento) ──────────────────

func _do_use_or_equip(item: Dictionary, cat: Dictionary) -> void:
	if cat.get("equip_slot", "") != "":
		_do_equip_item(item, cat)
	elif cat.get("type", "") == "consumable":
		_do_use_item(item)

func _do_use_item(item: Dictionary) -> void:
	var inv_id : String = str(item.get("id", ""))
	if inv_id == "":
		return
	WsClient.send({"type": "USE_ITEM", "payload": {"inventory_item_id": inv_id}})
	await get_tree().create_timer(0.3).timeout   # aguarda o servidor consumir
	_load_inventory()

func _do_equip_item(item: Dictionary, cat: Dictionary) -> void:
	if cat.get("equip_slot", "") == "":
		return
	_detail_err.text = ""
	ApiClient.post(
		"/api/inventory/%s/equip" % _char_id,
		{"inventory_item_id": item.get("id", "")},
		_on_equip_resp
	)

func _on_equip_resp(code: int, _data) -> void:
	if code == 200:
		_load_inventory()
	else:
		_detail_err.text = "Erro ao equipar."
		_detail_box.visible = true

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
