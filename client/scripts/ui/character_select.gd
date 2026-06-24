extends Control

@onready var _slots_grid    : GridContainer = $VBox/Scroll/Grid
@onready var _create_panel  : Panel         = $CreatePanel
@onready var _create_name   : LineEdit      = $CreatePanel/VBox/Name
@onready var _create_error  : Label         = $CreatePanel/VBox/Error

var _characters: Array = []

func _ready() -> void:
	_create_panel.visible = false
	_load_characters()

# ── Carrega personagens ───────────────────────────────────────────────────────

func _load_characters() -> void:
	ApiClient.get_req("/api/characters", func(code: int, data):
		if code != 200 or data == null:
			return
		_characters = data
		_render_slots()
	)

func _render_slots() -> void:
	for child in _slots_grid.get_children():
		child.queue_free()

	for i in range(9):
		var slot := _build_slot(i)
		_slots_grid.add_child(slot)

func _build_slot(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 160)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	if index < _characters.size():
		var ch: Dictionary = _characters[index]
		var name_lbl := Label.new()
		name_lbl.text = ch.get("name", "?")
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 16)

		var info_lbl := Label.new()
		info_lbl.text = "%s  Lv.%d" % [ch.get("class_id", "novice").capitalize(), ch.get("level", 1)]
		info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_lbl.add_theme_font_size_override("font_size", 12)
		info_lbl.modulate = Color(0.7, 0.9, 1.0)

		var play_btn := Button.new()
		play_btn.text = "Jogar"
		play_btn.pressed.connect(func(): _on_play_pressed(ch))

		vbox.add_child(name_lbl)
		vbox.add_child(info_lbl)
		vbox.add_child(play_btn)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = "— vazio —"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(0.4, 0.4, 0.4)
		vbox.add_child(empty_lbl)

	return panel

# ── Jogar ─────────────────────────────────────────────────────────────────────

func _on_play_pressed(char_data: Dictionary) -> void:
	GameState.character = char_data
	WsClient.authenticate(char_data.get("id", ""))
	# Aguarda AUTH_OK antes de trocar de cena
	await WsClient.ws_connected
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

# ── Criar personagem ──────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	_create_name.text = ""
	_create_error.text = ""
	_create_panel.visible = true

func _on_confirm_create_pressed() -> void:
	var name_text := _create_name.text.strip_edges()
	if name_text.length() < 3:
		_create_error.text = "Nome deve ter ao menos 3 caracteres."
		return

	ApiClient.post("/api/characters", {"name": name_text, "class_id": "novice"},
		func(code: int, data):
			if code == 201:
				_create_panel.visible = false
				_load_characters()
			else:
				var msg := "Erro ao criar personagem."
				if data != null and data.has("detail"):
					msg = str(data["detail"])
				_create_error.text = msg
	)

func _on_cancel_create_pressed() -> void:
	_create_panel.visible = false

# ── Voltar ────────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	WsClient.disconnect_ws()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
