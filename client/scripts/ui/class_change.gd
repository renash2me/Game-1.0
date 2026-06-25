extends Control

signal class_chosen(class_id: String)
signal dismissed()

var _classes          : Array         = []
var _cards_container  : VBoxContainer
var _status_label     : Label
var _scroll           : ScrollContainer

func _ready() -> void:
	_build_ui()
	_fetch_classes()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(400, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "A Escolha do Sigil"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Você atingiu Lv.25! Escolha sua especialização:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.text = "Carregando..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 260)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.visible = false
	vbox.add_child(_scroll)

	_cards_container = VBoxContainer.new()
	_cards_container.add_theme_constant_override("separation", 6)
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_container)

	vbox.add_child(HSeparator.new())

	var later_btn := Button.new()
	later_btn.text = "Mais tarde"
	later_btn.pressed.connect(_on_dismiss)
	vbox.add_child(later_btn)

func _fetch_classes() -> void:
	var char_id := str(GameState.character.get("id", ""))
	ApiClient.get_req(
		"/api/characters/%s/available-classes" % char_id,
		func(code: int, data) -> void:
			if code == 200 and data is Array and data.size() > 0:
				_classes = data
				_status_label.visible = false
				_scroll.visible = true
				_build_cards()
			else:
				_status_label.text = "Nenhuma classe disponível no momento."
	)

func _build_cards() -> void:
	for cls in _classes:
		_build_card(cls)

func _build_card(cls: Dictionary) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = cls.get("name", cls.get("id", "?"))
	name_lbl.add_theme_font_size_override("font_size", 14)
	inner.add_child(name_lbl)

	var growth : Dictionary = cls.get("stat_growth", {})
	if not growth.is_empty():
		var parts : Array = []
		for stat in growth:
			parts.append("%s +%d/Lv" % [stat.to_upper(), growth[stat]])
		var growth_lbl := Label.new()
		growth_lbl.text = "  ".join(parts)
		growth_lbl.add_theme_font_size_override("font_size", 11)
		growth_lbl.modulate = Color(0.75, 0.9, 1.0)
		inner.add_child(growth_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP/Lv: %d  SP/Lv: %d" % [cls.get("hp_per_level", 5), cls.get("sp_per_level", 2)]
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_lbl.modulate = Color(0.8, 1.0, 0.8)
	inner.add_child(hp_lbl)

	var btn := Button.new()
	btn.text = "Selecionar"
	btn.pressed.connect(_on_class_selected.bind(cls.get("id", "")))
	inner.add_child(btn)

func _on_class_selected(class_id: String) -> void:
	var char_id := str(GameState.character.get("id", ""))
	ApiClient.post(
		"/api/characters/%s/class-change" % char_id,
		{"class_id": class_id},
		func(code: int, data) -> void:
			if code == 200 and data != null:
				CharacterData.apply_from_response(data)
				class_chosen.emit(class_id)
				visible = false
			else:
				var err := Label.new()
				err.text = "Erro ao mudar de classe. Tente novamente."
				err.modulate = Color(1.0, 0.3, 0.3)
				err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_cards_container.add_child(err)
	)

func _on_dismiss() -> void:
	visible = false
	dismissed.emit()
