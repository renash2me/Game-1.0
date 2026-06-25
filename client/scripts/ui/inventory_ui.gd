extends Control

# Abas: [label_botão, tipos_de_item_incluídos]
# Array vazia = catch-all (tudo que não está nas outras abas)
const TABS : Array = [
	["Consumíveis",  ["consumable", "zeny_bag"]],
	["Equipamentos", ["weapon", "armor"]],
	["Etc",          []],
]

var _all_items      : Array      = []
var _catalog        : Dictionary = {}   # item_id → item data do servidor
var _catalog_loaded : bool       = false
var _active_tab     : int        = 0
var _tab_btns       : Array      = []
var _list_box       : VBoxContainer
var _detail_visible : bool       = false
var _detail_box     : VBoxContainer
var _detail_name    : Label
var _detail_info    : Label
var _btn_equip      : Button
var _btn_refine     : Button
var _detail_err     : Label
var _selected_item  : Dictionary = {}
var _panel          : PanelContainer
var _drag_offset    : Vector2    = Vector2.ZERO
var _dragging       : bool       = false
var _char_id        : String     = ""

func _ready() -> void:
	_char_id = str(GameState.character.get("id", ""))
	_build_ui()
	call_deferred("_default_position")
	WsClient.message_received.connect(_on_ws_message)

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

func _on_ws_message(type: String, _payload: Dictionary) -> void:
	if type in ["DROP_TAKEN", "LEVEL_UP"] and visible:
		_load_inventory()

# ── Construção da UI ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0)   # sem escurecimento — inventário é janela flutuante
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(390, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# ── Barra de título ────────────────────────────────────────────────────────
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

	# ── Abas ──────────────────────────────────────────────────────────────────
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

	# ── Lista de itens ─────────────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	vbox.add_child(HSeparator.new())

	# ── Detalhe do item ────────────────────────────────────────────────────────
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

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	_detail_box.add_child(action_row)

	_btn_equip = Button.new()
	_btn_equip.text = "Equipar"
	_btn_equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_equip.visible = false
	_btn_equip.pressed.connect(_on_equip_pressed)
	action_row.add_child(_btn_equip)

	_btn_refine = Button.new()
	_btn_refine.text = "Refinar"
	_btn_refine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_refine.visible = false
	_btn_refine.pressed.connect(_on_refine_pressed)
	action_row.add_child(_btn_refine)

	var close_detail := Button.new()
	close_detail.text = "Fechar"
	close_detail.pressed.connect(_hide_detail)
	action_row.add_child(close_detail)

	_detail_err = Label.new()
	_detail_err.add_theme_font_size_override("font_size", 11)
	_detail_err.modulate = Color(1, 0.35, 0.35)
	_detail_err.text = ""
	_detail_box.add_child(_detail_err)

	vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Fechar Inventário (I)"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func(): visible = false)
	vbox.add_child(close_btn)

func _default_position() -> void:
	var vp := get_viewport()
	if vp == null or _panel == null:
		return
	var s := vp.get_visible_rect().size
	_panel.position = Vector2(s.x - 400.0, 40.0)

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
	var is_catch_all   : bool  = included_types.is_empty()

	for item in _all_items:
		# Itens equipados não aparecem no inventário — use o painel Equip (E)
		if item.get("is_equipped", false):
			continue

		var item_id    : String = item.get("item_id", "")
		var item_cat   : Dictionary = _catalog.get(item_id, {})
		var item_type  : String = item_cat.get("type", "")

		var matches := false
		if is_catch_all:
			matches = item_type not in all_tab_types
		else:
			matches = item_type in included_types

		if matches:
			_list_box.add_child(_build_item_row(item, item_cat))

	# Mensagem se aba vazia
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

	var name_str : String = cat.get("name", item.get("item_id", "?"))
	var qty      : int    = item.get("quantity", 1)
	var refine   : int    = item.get("refinement", 0)

	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(name_lbl)

	# Badge: quantidade ou refinamento
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 10)
	badge.custom_minimum_size = Vector2(36, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if refine > 0:
		badge.text = "+%d" % refine
		badge.modulate = Color(1.0, 0.85, 0.3)
	elif qty > 1:
		badge.text = "x%d" % qty
		badge.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(badge)

	var sel_btn := Button.new()
	sel_btn.text = ">"
	sel_btn.custom_minimum_size = Vector2(26, 0)
	sel_btn.add_theme_font_size_override("font_size", 10)
	sel_btn.pressed.connect(_select_item.bind(item, cat))
	row.add_child(sel_btn)

	return row

# ── Detalhe ───────────────────────────────────────────────────────────────────

func _select_item(item: Dictionary, cat: Dictionary) -> void:
	_selected_item = item
	_detail_err.text = ""

	var name_str : String = cat.get("name", item.get("item_id", "?"))
	var refine   : int    = item.get("refinement", 0)
	_detail_name.text = name_str + (" +%d" % refine if refine > 0 else "")

	_detail_info.text = _build_item_desc(item, cat)

	var has_slot : bool = cat.get("equip_slot", "") != ""
	_btn_equip.visible  = has_slot
	_btn_refine.visible = has_slot and refine < 7
	_btn_equip.disabled = false
	_btn_refine.disabled = false

	_detail_box.visible = true

func _build_item_desc(item: Dictionary, cat: Dictionary) -> String:
	var lines : Array = []

	var qty := item.get("quantity", 1)
	if qty > 1:
		lines.append("Quantidade: %d" % qty)

	match cat.get("type", ""):
		"weapon":
			var atk : int = cat.get("atk", 0)
			var matk : int = cat.get("matk", 0)
			var slots : int = cat.get("slots", 0)
			if atk  > 0: lines.append("ATK: %d" % atk)
			if matk > 0: lines.append("MATK: %d" % matk)
			if slots > 0: lines.append("Slots: %d" % slots)
		"armor":
			var def : int = cat.get("def", 0)
			var slots : int = cat.get("slots", 0)
			if def   > 0: lines.append("DEF: %d" % def)
			if slots > 0: lines.append("Slots: %d" % slots)
		"consumable":
			var effect : Dictionary = cat.get("effect", {})
			if effect.has("hp_restore"):
				lines.append("Restaura %d HP" % effect["hp_restore"])
			if effect.has("sp_restore"):
				lines.append("Restaura %d SP" % effect["sp_restore"])
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

	return "\n".join(lines)

func _hide_detail() -> void:
	_selected_item = {}
	_detail_box.visible = false
	_detail_err.text = ""

# ── Ações ─────────────────────────────────────────────────────────────────────

func _on_equip_pressed() -> void:
	if _selected_item.is_empty():
		return
	_btn_equip.disabled = true
	ApiClient.post(
		"/api/inventory/%s/equip" % _char_id,
		{"inventory_item_id": _selected_item.get("id", "")},
		_on_equip_resp
	)

func _on_equip_resp(code: int, _data) -> void:
	if code == 200:
		_load_inventory()
	else:
		_btn_equip.disabled = false
		_detail_err.text = "Erro ao equipar."

func _on_refine_pressed() -> void:
	if _selected_item.is_empty():
		return
	_btn_refine.disabled = true
	ApiClient.post(
		"/api/inventory/%s/refine" % _char_id,
		{"inventory_item_id": _selected_item.get("id", "")},
		_on_refine_resp
	)

func _on_refine_resp(code: int, data) -> void:
	if code == 200:
		_load_inventory()
	else:
		_btn_refine.disabled = false
		if data != null and data.has("detail"):
			_detail_err.text = str(data["detail"])
		else:
			_detail_err.text = "Erro ao refinar."

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
