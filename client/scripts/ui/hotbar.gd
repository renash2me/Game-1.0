extends Control
## Barra de ação — 4 barras x 12 slots, atalhos de teclado, salva por personagem.
##
## Atalhos: barra 1 = teclas 1..9 0 - = ; barra 2 = Shift+ ; barra 3 = Ctrl+ ;
## barra 4 = Alt+ . Botão direito num slot abre o seletor (consumíveis + skills
## ativas + Limpar). Botão esquerdo ou o atalho dispara o slot.
## Persistência: user://hotbar_<char_id>.cfg (local, por personagem).

const BARS := 4
const SLOTS := 12
const PHYS_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
const KEY_LABELS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
const MOD_PREFIX := ["", "⇧", "⌃", "⌥"]   # barra 0..3

var _char_id    : String     = ""
var _cfg_path   : String     = ""
var _assign     : Dictionary = {}    # "bar_slot" -> {kind, id, name}
var _visible_bars : int      = 4
var _slot_btns  : Array      = []    # [bar][slot] -> Button
var _bar_rows   : Array      = []    # bar -> HBoxContainer
var _bar_btn    : Button     = null

var _item_catalog : Dictionary = {}  # item_id -> data (só consumíveis)
var _skills       : Array      = []  # skills ativas do personagem
var _picker       : PopupMenu  = null
var _picker_items : Array      = []  # paralelo aos itens do menu
var _picker_target : String    = ""  # "bar_slot"

func _ready() -> void:
	_char_id  = str(GameState.character.get("id", ""))
	_cfg_path = "user://hotbar_%s.cfg" % _char_id
	_build_ui()
	_load_config()
	_refresh_all_slots()
	_refresh_visible()
	ApiClient.get_req("/api/items", _on_items_loaded)
	ApiClient.get_req("/api/characters/%s/skills" % _char_id, _on_skills_loaded)

# ── UI ──────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.offset_bottom = -6.0
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(top)
	_bar_btn = Button.new()
	_bar_btn.add_theme_font_size_override("font_size", 9)
	_bar_btn.focus_mode = Control.FOCUS_NONE
	_bar_btn.pressed.connect(_cycle_bars)
	top.add_child(_bar_btn)

	# Monta barra 3..0 (VBox empilha de cima p/ baixo → barra 0 fica embaixo).
	_slot_btns.resize(BARS)
	_bar_rows.resize(BARS)
	for b in range(BARS - 1, -1, -1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 2)
		var btns : Array = []
		for s in range(SLOTS):
			btns.append(_make_slot(b, s, row))
		_slot_btns[b] = btns
		_bar_rows[b] = row
		vb.add_child(row)

func _make_slot(bar: int, slot: int, row: HBoxContainer) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(48, 42)
	btn.add_theme_font_size_override("font_size", 9)
	btn.clip_text = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.gui_input.connect(_on_slot_input.bind(bar, slot))
	row.add_child(btn)

	var key_lbl := Label.new()
	key_lbl.text = MOD_PREFIX[bar] + KEY_LABELS[slot]
	key_lbl.add_theme_font_size_override("font_size", 8)
	key_lbl.modulate = Color(0.7, 0.8, 1.0, 0.8)
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_lbl.position = Vector2(2, 1)
	btn.add_child(key_lbl)
	return btn

func _cycle_bars() -> void:
	_visible_bars = _visible_bars % BARS + 1
	_refresh_visible()
	_save_config()

func _refresh_visible() -> void:
	for b in range(BARS):
		_bar_rows[b].visible = b < _visible_bars
	_bar_btn.text = "Barras: %d" % _visible_bars

func _refresh_all_slots() -> void:
	for b in range(BARS):
		for s in range(SLOTS):
			_refresh_slot(b, s)

func _refresh_slot(bar: int, slot: int) -> void:
	var btn : Button = _slot_btns[bar][slot]
	var a = _assign.get("%d_%d" % [bar, slot], null)
	if a == null:
		btn.text = ""
		btn.tooltip_text = MOD_PREFIX[bar] + KEY_LABELS[slot]
	else:
		btn.text = str(a.get("name", "?"))
		btn.tooltip_text = "[%s] %s" % [MOD_PREFIX[bar] + KEY_LABELS[slot], a.get("name", "?")]

# ── Input ───────────────────────────────────────────────────────────────────

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

# ── Seletor (botão direito) ─────────────────────────────────────────────────

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
	for skill in _skills:
		_picker.add_item("Skill: %s" % str(skill.get("name", skill.get("id", "?"))), idx)
		_picker_items.append({"kind": "skill", "id": str(skill.get("id", "")), "name": str(skill.get("name", "?"))})
		idx += 1
	for item_id in _item_catalog:
		var it : Dictionary = _item_catalog[item_id]
		_picker.add_item("Item: %s" % str(it.get("name", item_id)), idx)
		_picker_items.append({"kind": "item", "id": item_id, "name": str(it.get("name", item_id))})
		idx += 1

	_picker.position = Vector2i(get_viewport().get_mouse_position())
	_picker.popup()

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

# ── Catálogos ───────────────────────────────────────────────────────────────

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

# ── Persistência (por personagem, local) ────────────────────────────────────

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("config", "visible_bars", _visible_bars)
	for key in _assign:
		cfg.set_value("slots", key, JSON.stringify(_assign[key]))
	cfg.save(_cfg_path)

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_cfg_path) != OK:
		return
	_visible_bars = int(cfg.get_value("config", "visible_bars", 4))
	if cfg.has_section("slots"):
		for key in cfg.get_section_keys("slots"):
			var parsed = JSON.parse_string(str(cfg.get_value("slots", key, "")))
			if parsed is Dictionary:
				_assign[key] = parsed
