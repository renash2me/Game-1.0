extends Control

# Popup flutuante de detalhes de item (botão direito no inventário).
# Arrastável, fechável com X ou clicando fora.

signal drop_requested(item: Dictionary)

var _item        : Dictionary = {}
var _panel       : PanelContainer
var _title_lbl   : Label
var _icon_panel  : PanelContainer
var _icon_lbl    : Label
var _stats_lbl   : Label
var _desc_lbl    : Label
var _drag_offset : Vector2 = Vector2.ZERO
var _dragging    : bool    = false

func _ready() -> void:
	_build_ui()

# ── API pública ────────────────────────────────────────────────────────────────

func show_item(item: Dictionary, cat: Dictionary, screen_pos: Vector2) -> void:
	_item = item
	var name_str : String = cat.get("name", item.get("item_id", "?"))
	var refine   : int    = item.get("refinement", 0)
	_title_lbl.text = name_str + (" +%d" % refine if refine > 0 else "")

	var itype : String = cat.get("type", "material")
	var style := StyleBoxFlat.new()
	style.bg_color = _type_color(itype)
	style.set_corner_radius_all(4)
	_icon_panel.add_theme_stylebox_override("panel", style)
	_icon_lbl.text = _type_letter(itype)

	_stats_lbl.text  = _build_stats(item, cat)
	_desc_lbl.text   = cat.get("description", "Sem descrição disponível.")

	visible = true
	call_deferred("_place_near", screen_pos)

# ── Construção ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # ver inventory_ui: não trava outras janelas

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Barra de título (arraste)
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 26)
	title_bar.add_theme_constant_override("separation", 4)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_drag)
	vbox.add_child(title_bar)

	_title_lbl = Label.new()
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 13)
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.add_child(_title_lbl)

	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(24, 0)
	x_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(x_btn)

	vbox.add_child(HSeparator.new())

	# Ícone + stats lado a lado
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 10)
	vbox.add_child(body_row)

	# Ícone placeholder colorido por tipo
	_icon_panel = PanelContainer.new()
	_icon_panel.custom_minimum_size = Vector2(64, 64)
	body_row.add_child(_icon_panel)

	_icon_lbl = Label.new()
	_icon_lbl.add_theme_font_size_override("font_size", 28)
	_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_icon_lbl.modulate = Color(1, 1, 1, 0.85)
	_icon_panel.add_child(_icon_lbl)

	_stats_lbl = Label.new()
	_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_stats_lbl.add_theme_font_size_override("font_size", 11)
	_stats_lbl.modulate = Color(0.85, 0.85, 0.85)
	_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_row.add_child(_stats_lbl)

	vbox.add_child(HSeparator.new())

	# Descrição
	_desc_lbl = Label.new()
	_desc_lbl.add_theme_font_size_override("font_size", 11)
	_desc_lbl.modulate = Color(0.75, 0.85, 0.75)
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_desc_lbl)

	var drop_btn := Button.new()
	drop_btn.text = "Largar 1 no chão"
	drop_btn.modulate = Color(1.0, 0.8, 0.6)
	drop_btn.pressed.connect(_on_drop_pressed)
	vbox.add_child(drop_btn)

func _on_drop_pressed() -> void:
	drop_requested.emit(_item)
	visible = false

# ── Posicionamento ─────────────────────────────────────────────────────────────

func _place_near(hint: Vector2) -> void:
	_panel.position = hint
	# Clamp para não sair da tela
	var vp := Vector2(DisplayServer.window_get_size())
	var sz  := _panel.size
	_panel.position.x = clamp(_panel.position.x, 0.0, max(0.0, vp.x - sz.x))
	_panel.position.y = clamp(_panel.position.y, 0.0, max(0.0, vp.y - sz.y))

# ── Drag ──────────────────────────────────────────────────────────────────────

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
			_panel.position = get_local_mouse_position() + _drag_offset
		elif event is InputEventMouseButton and not event.pressed:
			_dragging = false
		return
	# Fechar ao clicar fora do painel
	if event is InputEventMouseButton and event.pressed:
		var rect := Rect2(_panel.position, _panel.size)
		if not rect.has_point(get_local_mouse_position()):
			visible = false

# ── Helpers de conteúdo ───────────────────────────────────────────────────────

func _build_stats(item: Dictionary, cat: Dictionary) -> String:
	var lines : Array = []
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
			var eff : Dictionary = cat.get("effect", {})
			if eff.has("hp_restore"): lines.append("Restaura %d HP" % eff["hp_restore"])
			if eff.has("sp_restore"): lines.append("Restaura %d SP" % eff["sp_restore"])
		"zeny_bag":
			lines.append("Contém %d zeny" % cat.get("zeny_amount", 0))
		"card":
			var eff : Dictionary = cat.get("effect", {})
			for stat in eff:
				lines.append("%s +%d" % [stat.to_upper(), eff[stat]])

	var refine : int = item.get("refinement", 0)
	if refine > 0:
		lines.append("Refinamento: +%d" % refine)

	var cards : Array = item.get("cards", [])
	if not cards.is_empty():
		lines.append("Cartas: " + ", ".join(cards))

	var weight : int = cat.get("weight", 0)
	if weight > 0:
		lines.append("Peso: %.1f" % (weight / 10.0))

	var req : Dictionary = cat.get("requirements", {})
	if req.has("level"):
		lines.append("Nível mín.: %d" % req["level"])

	return "\n".join(lines) if not lines.is_empty() else "(sem atributos)"

func _type_color(t: String) -> Color:
	match t:
		"weapon":    return Color(0.75, 0.18, 0.18)
		"armor":     return Color(0.18, 0.36, 0.75)
		"consumable":return Color(0.18, 0.62, 0.28)
		"zeny_bag":  return Color(0.80, 0.70, 0.10)
		"card":      return Color(0.60, 0.15, 0.80)
		"material":  return Color(0.40, 0.40, 0.40)
	return Color(0.30, 0.30, 0.30)

func _type_letter(t: String) -> String:
	match t:
		"weapon":    return "W"
		"armor":     return "A"
		"consumable":return "+"
		"zeny_bag":  return "Z"
		"card":      return "*"
		"material":  return "M"
	return "?"
