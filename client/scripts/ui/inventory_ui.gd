extends Control

@onready var _grid         : GridContainer = $Panel/VBox/Scroll/Grid
@onready var _detail_panel : Panel         = $Detail
@onready var _detail_name  : Label         = $Detail/VBox/Name
@onready var _detail_info  : Label         = $Detail/VBox/Info
@onready var _btn_equip    : Button        = $Detail/VBox/BtnEquip
@onready var _btn_unequip  : Button        = $Detail/VBox/BtnUnequip
@onready var _btn_refine   : Button        = $Detail/VBox/BtnRefine
@onready var _detail_err   : Label         = $Detail/VBox/Error

var _items           : Array  = []
var _selected_idx    : int    = -1
var _char_id         : String = ""
var _pending_item_id : String = ""

func _ready() -> void:
	_char_id = str(GameState.character.get("id", ""))
	_detail_panel.visible = false
	_btn_equip.pressed.connect(_on_equip_pressed)
	_btn_unequip.pressed.connect(_on_unequip_pressed)
	_btn_refine.pressed.connect(_on_refine_pressed)
	WsClient.message_received.connect(_on_ws_message)

func _on_visibility_changed() -> void:
	if visible:
		_load_inventory()

# ── Carrega inventário ────────────────────────────────────────────────────────

func _load_inventory() -> void:
	ApiClient.get_req("/api/inventory/" + _char_id, _on_inventory_loaded)

func _on_inventory_loaded(code: int, data) -> void:
	if code != 200 or data == null:
		return
	_items = data
	_render_grid()

func _render_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	for i in range(_items.size()):
		var item: Dictionary = _items[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(60, 60)
		var label: String = item.get("item_id", "?")
		if item.get("is_equipped", false):
			label += " [E]"
		if item.get("refinement", 0) > 0:
			label += " +%d" % item.get("refinement", 0)
		btn.text = label
		btn.tooltip_text = "x%d" % item.get("quantity", 1)
		btn.pressed.connect(_select_item.bind(i))
		_grid.add_child(btn)

func _select_item(idx: int) -> void:
	_selected_idx = idx
	_detail_err.text = ""
	var item: Dictionary = _items[idx]

	_detail_name.text = item.get("item_id", "?")
	_detail_info.text = (
		"Qtd: %d\n" % item.get("quantity", 1) +
		"Slot: %s\n" % str(item.get("equip_slot", "")) +
		"Refinamento: +%d\n" % item.get("refinement", 0) +
		"Equipado: %s" % ("Sim" if item.get("is_equipped", false) else "Nao")
	)

	var has_slot: bool = item.get("equip_slot", "") != ""
	_btn_equip.visible   = has_slot and not item.get("is_equipped", false)
	_btn_unequip.visible = has_slot and item.get("is_equipped", false)
	_btn_refine.visible  = has_slot and item.get("refinement", 0) < 7
	_detail_panel.visible = true

# ── Ações ─────────────────────────────────────────────────────────────────────

func _on_equip_pressed() -> void:
	if _selected_idx < 0:
		return
	var item: Dictionary = _items[_selected_idx]
	_pending_item_id = item.get("id", "")
	ApiClient.post("/api/inventory/%s/equip" % _char_id,
		{"inventory_item_id": _pending_item_id}, _on_equip_response)

func _on_equip_response(code: int, _data) -> void:
	if code == 200:
		_load_inventory()
		_detail_panel.visible = false
	else:
		_detail_err.text = "Erro ao equipar."

func _on_unequip_pressed() -> void:
	if _selected_idx < 0:
		return
	var item: Dictionary = _items[_selected_idx]
	_pending_item_id = item.get("id", "")
	ApiClient.post("/api/inventory/%s/unequip" % _char_id,
		{"inventory_item_id": _pending_item_id}, _on_unequip_response)

func _on_unequip_response(code: int, _data) -> void:
	if code == 200:
		_load_inventory()
		_detail_panel.visible = false
	else:
		_detail_err.text = "Erro ao desequipar."

func _on_refine_pressed() -> void:
	if _selected_idx < 0:
		return
	var item: Dictionary = _items[_selected_idx]
	_pending_item_id = item.get("id", "")
	ApiClient.post("/api/inventory/%s/refine" % _char_id,
		{"inventory_item_id": _pending_item_id}, _on_refine_response)

func _on_refine_response(code: int, data) -> void:
	if code == 200:
		_load_inventory()
		_detail_panel.visible = false
	else:
		var msg: String = "Erro ao refinar."
		if data != null and data.has("detail"):
			msg = str(data["detail"])
		_detail_err.text = msg

# ── WS: atualiza ao receber drop ──────────────────────────────────────────────

func _on_ws_message(type: String, _payload: Dictionary) -> void:
	if type in ["DROP_TAKEN", "LEVEL_UP"] and visible:
		_load_inventory()
