extends Node2D

# ── Referências de cena ───────────────────────────────────────────────────────
@onready var _player_layer : Node2D    = $Layers/Players
@onready var _mob_layer    : Node2D    = $Layers/Mobs
@onready var _drop_layer   : Node2D    = $Layers/Drops
@onready var _camera       : Camera2D  = $Camera2D
@onready var _hud          : CanvasLayer = $HUD
@onready var _chat_ui      : Control   = $HUD/Chat
@onready var _inv_ui       : Control   = $HUD/Inventory
var _local_name : String = ""

# ── Entidades no mapa ─────────────────────────────────────────────────────────
var _players : Dictionary = {}   # char_id → Sprite2D
var _mobs    : Dictionary = {}   # instance_id → mob node
var _drops   : Dictionary = {}   # drop_id → drop node

# ── Movimento ─────────────────────────────────────────────────────────────────
const MOVE_SPEED : float = 120.0
const SEND_INTERVAL : float = 0.1
var _move_target : Vector2 = Vector2.ZERO
var _moving : bool = false
var _send_timer : float = 0.0
var _last_sent  : Vector2 = Vector2.ZERO

func _ready() -> void:
	_local_name = str(GameState.character.get("name", ""))
	CharacterData.init_from_character(GameState.character)

	var px : float = GameState.character.get("pos_x", 0.0)
	var py : float = GameState.character.get("pos_y", 0.0)
	_move_target = Vector2(px, py)
	_ensure_local_player(px, py)
	_camera.position = Vector2(px, py)

	# Conecta mensagens WS
	WsClient.message_received.connect(_on_ws_message)
	WsClient.ws_disconnected.connect(_on_ws_disconnected)

	# Carrega mapa
	var map_id : String = GameState.character.get("current_map", "starter_village")
	MapManager.load_map(map_id)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _inv_ui.visible:
				return
			var target := get_global_mouse_position()
			if Input.is_action_pressed("attack"):
				_try_attack_at(target)
			else:
				_move_target = target
				_moving = true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_pickup_at(get_global_mouse_position())
	elif event.is_action_pressed("inventory"):
		_inv_ui.visible = !_inv_ui.visible

# ── Process loop ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _moving:
		return

	var local_node := _get_local_player_node()
	if local_node == null:
		return

	var current := local_node.position
	var dir := (_move_target - current)
	if dir.length() < 2.0:
		local_node.position = _move_target
		_moving = false
		_broadcast_move(_move_target)
		return

	local_node.position += dir.normalized() * MOVE_SPEED * delta
	_camera.position = local_node.position

	# Envia posição a cada SEND_INTERVAL
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_INTERVAL
		var pos := local_node.position
		if pos.distance_to(_last_sent) > 1.0:
			_broadcast_move(pos)
			_last_sent = pos

func _broadcast_move(pos: Vector2) -> void:
	WsClient.send({
		"type": "MOVE",
		"payload": {"x": pos.x, "y": pos.y}
	})

# ── Ataque ────────────────────────────────────────────────────────────────────

func _try_attack_at(pos: Vector2) -> void:
	var best_id := ""
	var best_dist := 80.0  # alcance máximo em pixels
	for instance_id in _mobs:
		var mob_node = _mobs[instance_id]
		var d := mob_node.position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_id = instance_id
	if best_id != "":
		WsClient.send({"type": "ATTACK", "payload": {"target_id": best_id, "attack_type": "melee"}})

# ── Pickup ────────────────────────────────────────────────────────────────────

func _try_pickup_at(pos: Vector2) -> void:
	var best_id := ""
	var best_dist := 60.0
	for drop_id in _drops:
		var dn = _drops[drop_id]
		if dn.position.distance_to(pos) < best_dist:
			best_dist = dn.position.distance_to(pos)
			best_id = drop_id
	if best_id != "":
		WsClient.send({"type": "PICKUP", "payload": {"drop_id": best_id}})

# ── WebSocket Messages ────────────────────────────────────────────────────────

func _on_ws_message(type: String, payload: Dictionary) -> void:
	match type:
		"MAP_PLAYERS":  _handle_map_players(payload)
		"MOB_SPAWN":    _handle_mob_spawn(payload)
		"PLAYER_MOVE":  _handle_player_move(payload)
		"MOB_MOVE":     _handle_mob_move(payload)
		"PLAYER_JOIN":  _handle_player_join(payload)
		"PLAYER_LEAVE": _handle_player_leave(payload)
		"MOB_DEATH":    _handle_mob_death(payload)
		"DROP_APPEAR":  _handle_drop_appear(payload)
		"DROP_TAKEN":   _handle_drop_taken(payload)
		"DAMAGE":       _handle_damage(payload)
		"LEVEL_UP":     _handle_level_up(payload)
		"MAP_CHANGE":   _handle_map_change(payload)

func _handle_map_players(payload: Dictionary) -> void:
	for p in payload.get("players", []):
		var cid : String = p.get("character_id", "")
		var px : float = p.get("x", 0.0)
		var py : float = p.get("y", 0.0)
		var pname : String = p.get("name", "?")
		if cid == str(GameState.character.get("id", "")):
			_ensure_local_player(px, py)
		else:
			_ensure_remote_player(cid, pname, px, py)

func _handle_mob_spawn(payload: Dictionary) -> void:
	for mob in payload.get("mobs", []):
		_spawn_mob(mob)

func _handle_player_move(payload: Dictionary) -> void:
	var cid : String = payload.get("character_id", "")
	var pos := Vector2(payload.get("x", 0.0), payload.get("y", 0.0))
	if cid in _players:
		_players[cid].position = pos

func _handle_mob_move(payload: Dictionary) -> void:
	var iid : String = payload.get("instance_id", "")
	var pos := Vector2(payload.get("x", 0.0), payload.get("y", 0.0))
	if iid in _mobs:
		_mobs[iid].position = pos

func _handle_player_join(payload: Dictionary) -> void:
	var cid : String = payload.get("character_id", "")
	var pname : String = payload.get("name", "?")
	var pos := Vector2(payload.get("x", 0.0), payload.get("y", 0.0))
	_ensure_remote_player(cid, pname, pos.x, pos.y)

func _handle_player_leave(payload: Dictionary) -> void:
	var cid : String = payload.get("character_id", "")
	if cid in _players:
		_players[cid].queue_free()
		_players.erase(cid)

func _handle_mob_death(payload: Dictionary) -> void:
	var iid : String = payload.get("instance_id", "")
	if iid in _mobs:
		_mobs[iid].queue_free()
		_mobs.erase(iid)

func _handle_drop_appear(payload: Dictionary) -> void:
	var drop_id : String = payload.get("drop_id", "")
	var pos := Vector2(payload.get("x", 0.0), payload.get("y", 0.0))
	var node := _build_drop_node(drop_id, pos)
	_drop_layer.add_child(node)
	_drops[drop_id] = node

func _handle_drop_taken(payload: Dictionary) -> void:
	var drop_id : String = payload.get("drop_id", "")
	if drop_id in _drops:
		_drops[drop_id].queue_free()
		_drops.erase(drop_id)

func _handle_damage(payload: Dictionary) -> void:
	var target  : String = payload.get("target", "")
	var dmg     : int    = payload.get("damage", 0)
	var new_hp  : int    = payload.get("hp", CharacterData.hp)
	var new_mhp : int    = payload.get("max_hp", CharacterData.max_hp)
	var my_id   : String = str(GameState.character.get("id", ""))
	if target == my_id:
		CharacterData.apply_damage(new_hp, new_mhp)
	var pos := Vector2.ZERO
	if target in _players:
		pos = _players[target].position
	elif target in _mobs:
		pos = _mobs[target].position
	if pos != Vector2.ZERO:
		_spawn_damage_label(pos, str(dmg))

func _handle_level_up(payload: Dictionary) -> void:
	CharacterData.apply_level_up(
		payload.get("new_level", CharacterData.level),
		payload.get("stat_points_gained", 0),
		payload.get("skill_points_gained", 0)
	)
	CharacterData.apply_xp(
		payload.get("xp", CharacterData.xp),
		payload.get("xp_to_next", CharacterData.xp_to_next)
	)

func _handle_map_change(payload: Dictionary) -> void:
	var map_id : String = payload.get("map_id", "")
	GameState.character["current_map"] = map_id
	GameState.character["pos_x"] = payload.get("pos_x", 0.0)
	GameState.character["pos_y"] = payload.get("pos_y", 0.0)
	MapManager.load_map(map_id)
	get_tree().reload_current_scene()

# ── Utilitários de nó ─────────────────────────────────────────────────────────

func _ensure_local_player(px: float, py: float) -> void:
	var my_id := str(GameState.character.get("id", "__local__"))
	if my_id not in _players:
		var node := _build_player_node(_local_name, Color.CYAN)
		node.position = Vector2(px, py)
		_player_layer.add_child(node)
		_players[my_id] = node
		_camera.position = node.position

func _ensure_remote_player(cid: String, pname: String, px: float, py: float) -> void:
	if cid not in _players:
		var node := _build_player_node(pname, Color.WHITE)
		node.position = Vector2(px, py)
		_player_layer.add_child(node)
		_players[cid] = node

func _get_local_player_node() -> Node2D:
	var my_id := str(GameState.character.get("id", "__local__"))
	return _players.get(my_id, null)

func _build_player_node(pname: String, color: Color) -> Node2D:
	var root := Node2D.new()

	var sprite := ColorRect.new()
	sprite.size = Vector2(16, 24)
	sprite.position = Vector2(-8, -24)
	sprite.color = color
	root.add_child(sprite)

	var lbl := Label.new()
	lbl.text = pname
	lbl.position = Vector2(-24, -40)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = Color(1, 1, 0.6)
	root.add_child(lbl)

	return root

func _spawn_mob(mob: Dictionary) -> void:
	var iid : String = mob.get("instance_id", "")
	if iid in _mobs:
		return
	var root := Node2D.new()
	var sprite := ColorRect.new()
	sprite.size = Vector2(16, 16)
	sprite.position = Vector2(-8, -16)
	sprite.color = Color(1.0, 0.3, 0.3)
	root.add_child(sprite)

	var lbl := Label.new()
	lbl.text = mob.get("monster_id", "mob")
	lbl.position = Vector2(-16, -28)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate = Color(1.0, 0.5, 0.5)
	root.add_child(lbl)

	root.position = Vector2(mob.get("x", 0.0), mob.get("y", 0.0))
	_mob_layer.add_child(root)
	_mobs[iid] = root

func _build_drop_node(_drop_id: String, pos: Vector2) -> Node2D:
	var root := Node2D.new()
	var dot := ColorRect.new()
	dot.size = Vector2(8, 8)
	dot.position = Vector2(-4, -4)
	dot.color = Color(1.0, 1.0, 0.2)
	root.add_child(dot)
	root.position = pos
	return root

func _spawn_damage_label(pos: Vector2, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(-10, -20)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(1.0, 0.2, 0.2)
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position", lbl.position + Vector2(0, -30), 0.8)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.tween_callback(lbl.queue_free)

# ── Desconexão ────────────────────────────────────────────────────────────────

func _on_ws_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
