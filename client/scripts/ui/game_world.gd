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
var _moving      : bool    = false
var _left_held   : bool    = false
var _send_timer  : float   = 0.0
var _last_sent   : Vector2 = Vector2.ZERO

func _ready() -> void:
	_local_name = str(GameState.character.get("name", ""))
	CharacterData.apply_from_response(GameState.character)
	_add_ground()

	# Inventário e chat começam escondidos
	_inv_ui.visible = false
	_chat_ui.visible = false

	var px : float = GameState.character.get("pos_x", 0.0)
	var py : float = GameState.character.get("pos_y", 0.0)
	_move_target = Vector2(px, py)
	_ensure_local_player(px, py)
	_camera.position = Vector2(px, py)

	WsClient.message_received.connect(_on_ws_message)
	WsClient.ws_disconnected.connect(_on_ws_disconnected)

	var map_id : String = GameState.character.get("current_map", "starter_village")
	MapManager.load_map(map_id)

func _add_ground() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var ground := ColorRect.new()
	ground.color = Color(0.17, 0.24, 0.12)
	ground.size = Vector2(8000, 8000)
	ground.position = Vector2(-4000, -4000)
	layer.add_child(ground)
	# Grade sutil para dar sensacao de profundidade
	for gx in range(-20, 21):
		var line := ColorRect.new()
		line.color = Color(0.0, 0.0, 0.0, 0.08)
		line.size = Vector2(1, 8000)
		line.position = Vector2(gx * 64 - 0.5, -4000)
		layer.add_child(line)
	for gy in range(-20, 21):
		var line := ColorRect.new()
		line.color = Color(0.0, 0.0, 0.0, 0.08)
		line.size = Vector2(8000, 1)
		line.position = Vector2(-4000, gy * 64 - 0.5)
		layer.add_child(line)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _inv_ui.visible:
					return
				_left_held = true
				var target := get_global_mouse_position()
				if Input.is_action_pressed("attack"):
					_try_attack_at(target)
				else:
					_move_target = target
					_moving = true
					_spawn_click_marker(target)
			else:
				_left_held = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_pickup_at(get_global_mouse_position())
	elif event is InputEventMouseMotion and _left_held:
		if not _inv_ui.visible and not Input.is_action_pressed("attack"):
			_move_target = get_global_mouse_position()
			_moving = true
	elif event.is_action_pressed("inventory"):
		_inv_ui.visible = !_inv_ui.visible

func _spawn_click_marker(world_pos: Vector2) -> void:
	var marker := Node2D.new()
	add_child(marker)
	marker.position = world_pos

	var outer := ColorRect.new()
	outer.size = Vector2(18, 18)
	outer.position = Vector2(-9, -9)
	outer.color = Color(1.0, 1.0, 1.0, 0.75)
	marker.add_child(outer)

	var inner := ColorRect.new()
	inner.size = Vector2(6, 6)
	inner.position = Vector2(-3, -3)
	inner.color = Color(1.0, 0.9, 0.3, 1.0)
	marker.add_child(inner)

	var tw := create_tween()
	tw.tween_property(marker, "scale", Vector2(1.8, 1.8), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(outer, "modulate:a", 0.0, 0.22)
	tw.tween_callback(marker.queue_free)

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
		"payload": {
			"x": pos.x,
			"y": pos.y,
			"map_id": GameState.character.get("current_map", "starter_village")
		}
	})

# ── Ataque ────────────────────────────────────────────────────────────────────

func _try_attack_at(pos: Vector2) -> void:
	var best_id := ""
	var best_dist := 80.0  # alcance máximo em pixels
	for instance_id in _mobs:
		var mob_node = _mobs[instance_id]
		var d: float = mob_node.position.distance_to(pos)
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
		var dn_dist: float = dn.position.distance_to(pos)
		if dn_dist < best_dist:
			best_dist = dn_dist
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

	# Sombra
	var shadow := ColorRect.new()
	shadow.size = Vector2(18, 6)
	shadow.position = Vector2(-9, -4)
	shadow.color = Color(0, 0, 0, 0.28)
	root.add_child(shadow)

	# Corpo
	var body := ColorRect.new()
	body.size = Vector2(14, 16)
	body.position = Vector2(-7, -22)
	body.color = color
	root.add_child(body)

	# Cabeca
	var head := ColorRect.new()
	head.size = Vector2(12, 11)
	head.position = Vector2(-6, -35)
	head.color = color.lightened(0.18)
	root.add_child(head)

	# Olhos
	var el := ColorRect.new()
	el.size = Vector2(3, 3)
	el.position = Vector2(-4, -32)
	el.color = Color(0.05, 0.05, 0.05)
	root.add_child(el)

	var er := ColorRect.new()
	er.size = Vector2(3, 3)
	er.position = Vector2(1, -32)
	er.color = Color(0.05, 0.05, 0.05)
	root.add_child(er)

	# Nome
	var lbl := Label.new()
	lbl.text = pname
	lbl.position = Vector2(-28, -50)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = Color(1.0, 1.0, 0.7)
	root.add_child(lbl)

	return root

func _spawn_mob(mob: Dictionary) -> void:
	var iid : String = mob.get("instance_id", "")
	if iid in _mobs:
		return
	var mob_id : String = mob.get("monster_id", "mob")
	var root := Node2D.new()

	# Sombra
	var shadow := ColorRect.new()
	shadow.size = Vector2(22, 6)
	shadow.position = Vector2(-11, -4)
	shadow.color = Color(0, 0, 0, 0.25)
	root.add_child(shadow)

	# Corpo arredondado (simulado com rects sobrepostos)
	var body := ColorRect.new()
	body.size = Vector2(20, 16)
	body.position = Vector2(-10, -20)
	body.color = Color(0.95, 0.3, 0.3)
	root.add_child(body)

	var body_top := ColorRect.new()
	body_top.size = Vector2(16, 4)
	body_top.position = Vector2(-8, -24)
	body_top.color = Color(0.95, 0.3, 0.3)
	root.add_child(body_top)

	# Olhos brancos + pupila
	var ew_l := ColorRect.new()
	ew_l.size = Vector2(5, 5)
	ew_l.position = Vector2(-7, -18)
	ew_l.color = Color(1, 1, 1)
	root.add_child(ew_l)

	var ep_l := ColorRect.new()
	ep_l.size = Vector2(2, 3)
	ep_l.position = Vector2(-6, -17)
	ep_l.color = Color(0.1, 0.05, 0.05)
	root.add_child(ep_l)

	var ew_r := ColorRect.new()
	ew_r.size = Vector2(5, 5)
	ew_r.position = Vector2(2, -18)
	ew_r.color = Color(1, 1, 1)
	root.add_child(ew_r)

	var ep_r := ColorRect.new()
	ep_r.size = Vector2(2, 3)
	ep_r.position = Vector2(3, -17)
	ep_r.color = Color(0.1, 0.05, 0.05)
	root.add_child(ep_r)

	# Nome do mob
	var lbl := Label.new()
	lbl.text = mob_id
	lbl.position = Vector2(-20, -35)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate = Color(1.0, 0.6, 0.6)
	root.add_child(lbl)

	root.position = Vector2(mob.get("x", 0.0), mob.get("y", 0.0))
	_mob_layer.add_child(root)
	_mobs[iid] = root

func _build_drop_node(_drop_id: String, pos: Vector2) -> Node2D:
	var root := Node2D.new()

	# Brilho externo
	var glow := ColorRect.new()
	glow.size = Vector2(14, 14)
	glow.position = Vector2(-7, -7)
	glow.color = Color(1.0, 0.9, 0.1, 0.35)
	root.add_child(glow)

	# Gema
	var gem := ColorRect.new()
	gem.size = Vector2(9, 9)
	gem.position = Vector2(-4.5, -4.5)
	gem.color = Color(1.0, 0.85, 0.0)
	root.add_child(gem)

	# Reflexo
	var shine := ColorRect.new()
	shine.size = Vector2(3, 3)
	shine.position = Vector2(-3.5, -3.5)
	shine.color = Color(1.0, 1.0, 0.95)
	root.add_child(shine)

	root.position = pos

	# Animacao de bobbing
	var tw := root.create_tween()
	tw.set_loops()
	tw.tween_property(root, "position:y", pos.y - 5.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(root, "position:y", pos.y, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	return root

func _spawn_damage_label(pos: Vector2, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	var offset := Vector2(randf_range(-8.0, 8.0), -20.0)
	lbl.position = pos + offset
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(1.0, 0.88, 0.1)
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position", lbl.position + Vector2(0, -42), 0.7)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tween.tween_callback(lbl.queue_free)

# ── Desconexão ────────────────────────────────────────────────────────────────

func _on_ws_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
