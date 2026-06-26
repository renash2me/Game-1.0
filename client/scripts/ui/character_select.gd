extends Control

@onready var _slots_grid    : GridContainer = $VBox/Scroll/Grid
@onready var _btn_select    : Button        = $VBox/ActionRow/BtnSelecionar
@onready var _btn_delete    : Button        = $VBox/ActionRow/BtnExcluir
@onready var _create_panel  : Panel         = $CreatePanel
@onready var _create_name   : LineEdit      = $CreatePanel/VBox/Name
@onready var _create_error  : Label         = $CreatePanel/VBox/Error
@onready var _delete_panel  : Panel         = $DeletePanel
@onready var _delete_msg    : Label         = $DeletePanel/VBox/Msg

var _characters: Array = []
var _slot_panels: Array = []
var _selected_index: int = -1

func _ready() -> void:
	_create_panel.visible = false
	_delete_panel.visible = false
	_load_characters()

# ── Carrega personagens ───────────────────────────────────────────────────────

func _load_characters() -> void:
	ApiClient.get_req("/api/characters", _on_characters_loaded)

func _on_characters_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	_characters = data
	_render_slots()

func _render_slots() -> void:
	for child in _slots_grid.get_children():
		child.queue_free()
	_slot_panels.clear()
	_selected_index = -1
	for i in range(9):
		var slot := _build_slot(i)
		_slots_grid.add_child(slot)
		_slot_panels.append(slot)
	_update_slot_highlights()
	_update_action_buttons()

func _build_slot(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 160)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	if index < _characters.size():
		var ch: Dictionary = _characters[index]
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(_on_slot_input.bind(index))

		var name_lbl := Label.new()
		name_lbl.text = str(ch.get("name", "?"))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var info_lbl := Label.new()
		info_lbl.text = "%s  Lv.%d" % [str(ch.get("class_id", "novice")).capitalize(), int(ch.get("level", 1))]
		info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_lbl.add_theme_font_size_override("font_size", 12)
		info_lbl.modulate = Color(0.7, 0.9, 1.0)
		info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var zeny_lbl := Label.new()
		zeny_lbl.text = "z %d" % int(ch.get("zeny", 0))
		zeny_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zeny_lbl.add_theme_font_size_override("font_size", 11)
		zeny_lbl.modulate = Color(1.0, 0.85, 0.2)
		zeny_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		vbox.add_child(name_lbl)
		vbox.add_child(info_lbl)
		vbox.add_child(zeny_lbl)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = "— vazio —"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(0.4, 0.4, 0.4)
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(empty_lbl)

	return panel

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_selected_index = index
		_update_slot_highlights()
		_update_action_buttons()
		if event.double_click:
			_on_select_pressed()

func _update_slot_highlights() -> void:
	for i in range(_slot_panels.size()):
		_slot_panels[i].self_modulate = Color(1.0, 0.82, 0.3) if i == _selected_index else Color(1, 1, 1)

func _update_action_buttons() -> void:
	var valid := _selected_index >= 0 and _selected_index < _characters.size()
	_btn_select.disabled = not valid
	_btn_delete.disabled = not valid

func _selected_char() -> Dictionary:
	if _selected_index >= 0 and _selected_index < _characters.size():
		return _characters[_selected_index]
	return {}

# ── Selecionar / Jogar ────────────────────────────────────────────────────────

func _on_select_pressed() -> void:
	var ch := _selected_char()
	if ch.is_empty():
		return
	GameState.character = ch
	WsClient.authenticate(str(ch.get("id", "")))
	await WsClient.ws_connected
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

# ── Excluir personagem ────────────────────────────────────────────────────────

func _on_delete_pressed() -> void:
	var ch := _selected_char()
	if ch.is_empty():
		return
	_delete_msg.text = "O personagem \"%s\" e TODOS os seus itens e dinheiro serão apagados permanentemente.\nEsta ação não pode ser desfeita." % str(ch.get("name", "?"))
	_delete_panel.visible = true

func _on_cancel_delete_pressed() -> void:
	_delete_panel.visible = false

func _on_confirm_delete_pressed() -> void:
	var ch := _selected_char()
	if ch.is_empty():
		_delete_panel.visible = false
		return
	ApiClient.del("/api/characters/%s" % str(ch.get("id", "")), _on_delete_response)

func _on_delete_response(code: int, _data) -> void:
	_delete_panel.visible = false
	if code == 204 or code == 200:
		_load_characters()

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

	ApiClient.post("/api/characters", {"name": name_text, "class_id": "novice"}, _on_create_response)

func _on_create_response(code: int, data) -> void:
	if code == 201:
		_create_panel.visible = false
		_load_characters()
	else:
		var msg: String = "Erro ao criar personagem."
		if data != null and data.has("detail"):
			msg = str(data["detail"])
		_create_error.text = msg

func _on_cancel_create_pressed() -> void:
	_create_panel.visible = false

# ── Voltar ────────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	WsClient.disconnect_ws()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
