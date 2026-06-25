extends Control

const _STAT_DEFS := [
	["str",  "STR", "Força"],
	["agi",  "AGI", "Agilidade"],
	["vit",  "VIT", "Vitalidade"],
	["int_", "INT", "Inteligência"],
	["dex",  "DEX", "Destreza"],
	["luk",  "LUK", "Sorte"],
]

var _pending        : Dictionary = {}
var _current_labels : Dictionary = {}
var _pending_labels : Dictionary = {}
var _avail_label    : Label
var _apply_btn      : Button

func _ready() -> void:
	for d in _STAT_DEFS:
		_pending[d[0]] = 0
	_build_ui()
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(320, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Atributos"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_avail_label = Label.new()
	_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avail_label.add_theme_font_size_override("font_size", 12)
	_avail_label.modulate = Color(1.0, 0.9, 0.3)
	vbox.add_child(_avail_label)

	vbox.add_child(HSeparator.new())

	for d in _STAT_DEFS:
		_build_stat_row(vbox, d[0], d[1])

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
	close_btn.pressed.connect(func() -> void: visible = false)
	btn_row.add_child(close_btn)

func _build_stat_row(parent: Control, key: String, abbr: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = abbr
	name_lbl.custom_minimum_size = Vector2(32, 0)
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
	pending_lbl.custom_minimum_size = Vector2(30, 0)
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
		var p : int = _pending.get(key, 0)
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

func _on_apply_pressed() -> void:
	if _total_pending() == 0:
		return
	var char_id := str(GameState.character.get("id", ""))
	var body    := {}
	for key in _pending:
		if _pending[key] > 0:
			body[key] = _pending[key]
	_apply_btn.disabled = true
	ApiClient.post(
		"/api/characters/%s/allocate-stats" % char_id,
		body,
		func(code: int, data) -> void:
			if code == 200 and data != null:
				CharacterData.apply_from_response(data)
				for k in _pending:
					_pending[k] = 0
				_refresh()
			else:
				_apply_btn.disabled = false
	)
