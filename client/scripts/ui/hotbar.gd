extends Control
## Barra de ação — JANELA móvel/redimensionável, 4 barras x 12 slots, ícones,
## atalhos de teclado e atribuição por arrastar item/skill (drag-drop).
##
## Atalhos: barra 1 = teclas 1..9 0 - = ; barra 2 = Shift+ ; barra 3 = Ctrl+ ;
## barra 4 = Alt+ . Esquerdo/atalho dispara o slot; direito abre o seletor.
## Arrastar um consumível do inventário ou uma skill ativa para um slot atribui.
## Redimensionar (grip) esconde/mostra uma barra por vez.
## Persistência: user://hotbar_<char_id>.cfg (posição, nº de barras e atribuições).

const BARS = 4
const SLOTS = 12
const SLOT_SIZE = 40
const PHYS_KEYS = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
const KEY_LABELS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
const MOD_PREFIX = ["", "Sh+", "Ct+", "Al+"]   # barra 0..3

var _char_id      : String         = ""
var _cfg_path     : String         = ""
var _assign       : Dictionary     = {}    # "bar_slot" -> {kind,id,name,itype}
var _visible_bars : int            = 4
var _slots        : Array          = []    # [bar][slot] -> {btn,icon,letter}
var _bar_rows     : Array          = []    # bar -> HBoxContainer
var _bar_btn      : Button         = null
var _panel        : PanelContainer = null
var _bars_vb      : VBoxContainer  = null
var _saved_pos    : Vector2        = Vector2(-1.0, -1.0)

var _item_catalog : Dictionary     = {}    # item_id -> data (só consumíveis)
var _skills       : Array          = []    # skills ativas do personagem
var _picker       : PopupMenu      = null
var _picker_items : Array          = []
var _picker_target : String        = ""

# Drag/resize da janela
var _drag_offset  : Vector2        = Vector2.ZERO
var _dragging     : bool           = false
var _grip                          = null
var _resizing     : bool           = false
var _res_mouse    : Vector2        = Vector2.ZERO
var _res_bars     : int            = 4

func _ready() -> void:
	_char_id  = str(GameState.character.get("id", ""))
	_cfg_path = "user://hotbar_%s.cfg" % _char_id
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # raiz invisível ao mouse; só o _panel/grip capturam
	_build_ui()
	_load_config()
	_refresh_all_slots()
	_refresh_visible()
	get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_restore_or_center")
	ApiClient.get_req("/api/items", _on_items_loaded)
	ApiClient.get_req("/api/characters/%s/skills" % _char_id, _on_skills_loaded)

func _exit_tree() -> void:
	WindowManager.unregister(_panel)

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_panel.add_child(vb)

	# Barra de título (arraste) + botão de nº de barras
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 18)
	title_bar.add_theme_constant_override("separation", 4)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_drag)
	vb.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = ":: Atalhos"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.modulate = Color(0.7, 0.7, 0.7)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(title_lbl)

	_bar_btn = Button.new()
	_bar_btn.add_theme_font_size_override("font_size", 9)
	_bar_btn.focus_mode = Control.FOCUS_NONE
	_bar_btn.pressed.connect(_cycle_bars)
	title_bar.add_child(_bar_btn)

	# Barras de slots
	_bars_vb = VBoxContainer.new()
	_bars_vb.add_theme_constant_override("separation", 2)
	vb.add_child(_bars_vb)

	_slots.resize(BARS)
	_bar_rows.resize(BARS)
	# Empilha barra 3..0 (VBox de cima p/ baixo → barra 0 fica embaixo)
	for b in range(BARS - 1, -1, -1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var slot_list : Array = []
		for s in range(SLOTS):
			slot_list.append(_make_slot(b, s, row))
		_slots[b]    = slot_list
		_bar_rows[b] = row
		_bars_vb.add_child(row)

	# Grip de resize (canto inferior direito) — filho da raiz
	_grip = ColorRect.new()
	_grip.size = Vector2(12, 12)
	_grip.color = Color(0.55, 0.55, 0.55, 0.65)
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.gui_input.connect(_on_grip_input)
	add_child(_grip)

	WindowManager.register(_panel)

func _make_slot(bar: int, slot: int, row: HBoxContainer) -> Dictionary:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.gui_input.connect(_on_slot_input.bind(bar, slot))
	btn.set_drag_forwarding(_slot_drag.bind(bar, slot), _slot_can_drop.bind(bar, slot), _slot_drop.bind(bar, slot))
	row.add_child(btn)

	# Ícone (fundo colorido) — placeholder até termos sprites reais
	var icon := ColorRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2; icon.offset_top = 2; icon.offset_right = -2; icon.offset_bottom = -2
	icon.color = Color(0.0, 0.0, 0.0, 0.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	# Iniciais sobre o ícone
	var letter := Label.new()
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 15)
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(letter)

	# Atalho no canto
	var key_lbl := Label.new()
	key_lbl.text = MOD_PREFIX[bar] + KEY_LABELS[slot]
	key_lbl.add_theme_font_size_override("font_size", 8)
	key_lbl.modulate = Color(0.7, 0.85, 1.0, 0.9)
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_lbl.position = Vector2(2, 0)
	btn.add_child(key_lbl)

	return {"btn": btn, "icon": icon, "letter": letter}

func _cycle_bars() -> void:
	_visible_bars = _visible_bars % BARS + 1
	_refresh_visible()
	_save_config()

func _refresh_visible() -> void:
	for b in range(BARS):
		_bar_rows[b].visible = b < _visible_bars
	if _bar_btn != null:
		_bar_btn.text = "%d/%d" % [_visible_bars, BARS]
	call_deferred("_update_grip")

func _refresh_all_slots() -> void:
	for b in range(BARS):
		for s in range(SLOTS):
			_refresh_slot(b, s)

func _refresh_slot(bar: int, slot: int) -> void:
	var s : Dictionary = _slots[bar][slot]
	var icon : ColorRect = s["icon"]
	var letter : Label = s["letter"]
	var btn : Button = s["btn"]
	var a = _assign.get("%d_%d" % [bar, slot], null)
	if a == null:
		icon.color = Color(0.0, 0.0, 0.0, 0.0)
		letter.text = ""
		btn.tooltip_text = MOD_PREFIX[bar] + KEY_LABELS[slot]
	else:
		var kind : String = str(a.get("kind", ""))
		var nm   : String = str(a.get("name", "?"))
		icon.color  = Color(0.20, 0.42, 0.80, 0.9) if kind == "skill" else Color(0.20, 0.55, 0.28, 0.9)
		letter.text = nm.substr(0, 2)
		btn.tooltip_text = "[%s] %s" % [MOD_PREFIX[bar] + KEY_LABELS[slot], nm]

# ── Disparo (clique/atalho) ───────────────────────────────────────────────────

func _on_slot_input(event: InputEvent, bar: int, slot: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_trigger(bar, slot)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_open_picker(bar, slot)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var slot := PHYS_KEYS.find(event.physical_keycode)
	if slot == -1:
		return
	var bar := 0
	if event.shift_pressed:
		bar = 1
	elif event.ctrl_pressed:
		bar = 2
	elif event.alt_pressed:
		bar = 3
	if bar >= _visible_bars:
		return
	if _trigger(bar, slot):
		get_viewport().set_input_as_handled()

func _trigger(bar: int, slot: int) -> bool:
	var a = _assign.get("%d_%d" % [bar, slot], null)
	if a == null:
		return false
	var kind : String = str(a.get("kind", ""))
	var id   : String = str(a.get("id", ""))
	if kind == "item":
		WsClient.send({"type": "USE_ITEM", "payload": {"item_id": id}})
	elif kind == "skill":
		WsClient.send({"type": "CAST_SKILL", "payload": {"skill_id": id}})
	return true

# ── Drag-drop (atribuição) ────────────────────────────────────────────────────

func _slot_drag(_at: Vector2, _bar: int, _slot: int) -> Variant:
	return null   # não inicia arraste a partir do slot

func _slot_can_drop(_at: Vector2, data, _bar: int, _slot: int) -> bool:
	if not (data is Dictionary):
		return false
	var kind : String = str(data.get("kind", ""))
	if kind == "skill":
		return true
	if kind == "item":
		return str(data.get("itype", "")) == "consumable"
	return false

func _slot_drop(_at: Vector2, data, bar: int, slot: int) -> void:
	if not (data is Dictionary):
		return
	_assign["%d_%d" % [bar, slot]] = {
		"kind":  str(data.get("kind", "")),
		"id":    str(data.get("id", "")),
		"name":  str(data.get("name", "?")),
		"itype": str(data.get("itype", "")),
	}
	_refresh_slot(bar, slot)
	_save_config()

# ── Seletor (botão direito) ───────────────────────────────────────────────────

func _open_picker(bar: int, slot: int) -> void:
	_picker_target = "%d_%d" % [bar, slot]
	if _picker == null:
		_picker = PopupMenu.new()
		_picker.id_pressed.connect(_on_picker_pressed)
		add_child(_picker)
	_picker.clear()
	_picker_items.clear()

	_picker.add_item("— Limpar —", 0)
	_picker_items.append(null)

	var idx := 1
	var skill_icon := _swatch(Color(0.20, 0.42, 0.80))
	for skill in _skills:
		_picker.add_icon_item(skill_icon, "Skill: %s" % str(skill.get("name", skill.get("id", "?"))), idx)
		_picker_items.append({"kind": "skill", "id": str(skill.get("id", "")), "name": str(skill.get("name", "?"))})
		idx += 1
	var item_icon := _swatch(Color(0.20, 0.55, 0.28))
	for item_id in _item_catalog:
		var it : Dictionary = _item_catalog[item_id]
		_picker.add_icon_item(item_icon, "Item: %s" % str(it.get("name", item_id)), idx)
		_picker_items.append({"kind": "item", "id": item_id, "name": str(it.get("name", item_id)), "itype": "consumable"})
		idx += 1

	_picker.position = Vector2i(get_viewport().get_mouse_position())
	_picker.popup()

func _swatch(c: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _on_picker_pressed(id: int) -> void:
	if _picker_target == "":
		return
	if id == 0:
		_assign.erase(_picker_target)
	elif id < _picker_items.size():
		_assign[_picker_target] = _picker_items[id]
	var parts := _picker_target.split("_")
	_refresh_slot(int(parts[0]), int(parts[1]))
	_save_config()
	_picker_target = ""

# ── Catálogos ─────────────────────────────────────────────────────────────────

func _on_items_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	for entry in data:
		if entry.get("type", "") == "consumable":
			_item_catalog[entry.get("id", "")] = entry

func _on_skills_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	for skill in data:
		if skill.get("type", "") == "active":
			_skills.append(skill)

# ── Posição / Drag / Resize ───────────────────────────────────────────────────

func _on_viewport_resized() -> void:
	call_deferred("_clamp_to_screen")

func _restore_or_center() -> void:
	if _panel == null:
		return
	if _saved_pos.x >= 0.0:
		_panel.position = _saved_pos
	else:
		var vp := get_viewport_rect().size
		_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, vp.y - _panel.size.y - 8.0)
	_clamp_to_screen()

func _clamp_to_screen() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	_panel.position.x = clampf(_panel.position.x, 0.0, max(0.0, vp.x - 40.0))
	_panel.position.y = clampf(_panel.position.y, 0.0, max(0.0, vp.y - 24.0))
	_update_grip()

func _update_grip() -> void:
	if _grip == null or _panel == null:
		return
	_grip.position = _panel.position + _panel.size - Vector2(12, 12)

func _on_title_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_offset = _panel.position - get_local_mouse_position()

func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if event.pressed:
			_res_mouse = get_local_mouse_position()
			_res_bars  = _visible_bars

func _input(event: InputEvent) -> void:
	if _dragging:
		if event is InputEventMouseMotion:
			var raw := get_local_mouse_position() + _drag_offset
			_panel.position = WindowManager.snap_move(_panel, raw)
			_update_grip()
		elif event is InputEventMouseButton and not event.pressed:
			_dragging = false
			_save_config()
	if _resizing:
		if event is InputEventMouseMotion:
			var dy := get_local_mouse_position().y - _res_mouse.y
			var nb := clampi(_res_bars + int(round(dy / float(SLOT_SIZE + 2))), 1, BARS)
			if nb != _visible_bars:
				_visible_bars = nb
				_refresh_visible()
		elif event is InputEventMouseButton and not event.pressed:
			_resizing = false
			_save_config()

# ── Persistência (por personagem, local) ──────────────────────────────────────

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("config", "visible_bars", _visible_bars)
	if _panel != null:
		cfg.set_value("config", "pos_x", _panel.position.x)
		cfg.set_value("config", "pos_y", _panel.position.y)
	for key in _assign:
		cfg.set_value("slots", key, JSON.stringify(_assign[key]))
	cfg.save(_cfg_path)

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_cfg_path) != OK:
		return
	_visible_bars = int(cfg.get_value("config", "visible_bars", 4))
	var px = cfg.get_value("config", "pos_x", null)
	var py = cfg.get_value("config", "pos_y", null)
	if px != null and py != null:
		_saved_pos = Vector2(float(px), float(py))
	if cfg.has_section("slots"):
		for key in cfg.get_section_keys("slots"):
			var parsed = JSON.parse_string(str(cfg.get_value("slots", key, "")))
			if parsed is Dictionary:
				_assign[key] = parsed
