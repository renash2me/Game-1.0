extends Node3D

# ── Constantes ─────────────────────────────────────────────────────────────────
# Escala: 1 unidade de servidor = WORLD_SCALE unidades 3D.
# Com 0.025, mapa de 800 server units → 20 unidades 3D (confortável na câmera).
const WORLD_SCALE   : float  = 0.025
const CAM_OFFSET    := Vector3(0.0, 12.0, 8.5)   # offset relativo ao player
const CAM_ORTHO_DEF : float  = 10.0
const CAM_ORTHO_MIN : float  = 3.5
const CAM_ORTHO_MAX : float  = 22.0
const CAM_ZOOM_STEP : float  = 0.7
const MOVE_SPEED    : float  = 2.5               # 3D units/s ≈ 100 server/s
const SEND_INTERVAL : float  = 0.1

# ── Referências ────────────────────────────────────────────────────────────────
@onready var _player_layer : Node3D     = $Layers/Players
@onready var _mob_layer    : Node3D     = $Layers/Mobs
@onready var _drop_layer   : Node3D     = $Layers/Drops
@onready var _camera       : Camera3D   = $Camera3D
@onready var _hud          : CanvasLayer = $HUD
@onready var _inv_ui       : Control    = $HUD/Inventory

# ── Estado ─────────────────────────────────────────────────────────────────────
var _local_name  : String  = ""
var _coords_lbl           = null
var _cam_ortho   : float   = CAM_ORTHO_DEF
var _move_target : Vector3 = Vector3.ZERO
var _moving      : bool    = false
var _left_held   : bool    = false
var _send_timer  : float   = 0.0
var _last_sent   : Vector3 = Vector3.ZERO
var _players     : Dictionary = {}
var _mobs        : Dictionary = {}
var _drops       : Dictionary = {}

# ── Inicialização ──────────────────────────────────────────────────────────────

func _ready() -> void:
	_local_name = str(GameState.character.get("name", ""))
	CharacterData.apply_from_response(GameState.character)

	_setup_camera()
	_setup_world()

	_inv_ui.visible = false

	_coords_lbl = Label.new()
	_coords_lbl.add_theme_font_size_override("font_size", 11)
	_coords_lbl.modulate = Color(1.0, 1.0, 0.5, 0.85)
	_coords_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_coords_lbl)
	call_deferred("_anchor_coords_lbl")

	var px : float = GameState.character.get("pos_x", 0.0)
	var py : float = GameState.character.get("pos_y", 0.0)
	_move_target = _to_3d(px, py)
	_ensure_local_player(px, py)

	WsClient.message_received.connect(_on_ws_message)
	WsClient.ws_disconnected.connect(_on_ws_disconnected)
	MapManager.load_map(GameState.character.get("current_map", "starter_village"))

func _setup_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size       = _cam_ortho
	_camera.near       = 0.05
	_camera.far        = 600.0
	_camera.position   = CAM_OFFSET
	_camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)

func _setup_world() -> void:
	# Céu / fundo
	var env_node := WorldEnvironment.new()
	var env      := Environment.new()
	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.18)
	add_child(env_node)
	env_node.environment = env

	# Chão
	var ground := MeshInstance3D.new()
	var plane  := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.17, 0.24, 0.12)
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = gmat
	add_child(ground)

	# Grade de referência visual (linhas a cada 40 server units)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.18)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mesh_x := BoxMesh.new()
	mesh_x.size = Vector3(0.018, 0.002, 580.0)
	var mesh_z := BoxMesh.new()
	mesh_z.size = Vector3(580.0, 0.002, 0.018)

	for i in range(-15, 16):
		var step : float = i * 40.0 * WORLD_SCALE

		var lx := MeshInstance3D.new()
		lx.mesh              = mesh_x
		lx.material_override = line_mat
		lx.position          = Vector3(step, 0.001, 0.0)
		add_child(lx)

		var lz := MeshInstance3D.new()
		lz.mesh              = mesh_z
		lz.material_override = line_mat
		lz.position          = Vector3(0.0, 0.001, step)
		add_child(lz)

func _anchor_coords_lbl() -> void:
	if _coords_lbl == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	_coords_lbl.position = Vector2(8.0, vp_size.y - 24.0)

# ── Conversão de coordenadas ───────────────────────────────────────────────────

func _to_3d(sx: float, sy: float) -> Vector3:
	return Vector3(sx * WORLD_SCALE, 0.0, sy * WORLD_SCALE)

func _to_server(v: Vector3) -> Vector2:
	return Vector2(v.x / WORLD_SCALE, v.z / WORLD_SCALE)

# ── Raycast mouse → plano do chão (y = 0) ────────────────────────────────────

func _ground_at_mouse() -> Vector3:
	var mouse  := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	# Direção fixa: câmera SEMPRE aponta de CAM_OFFSET para (0,0.5,0) relativo ao player
	# normalize(Vector3(0,0.5,0) - CAM_OFFSET) = normalize(0,-11.5,-8.5) ≈ (0,-0.80420,-0.59441)
	var ground := Plane(Vector3.UP, 0.0)
	var hit    := ground.intersects_ray(origin, Vector3(0.0, -0.80420, -0.59441))
	if hit == null:
		return Vector3.ZERO
	return hit

# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_ortho  = clamp(_cam_ortho - CAM_ZOOM_STEP, CAM_ORTHO_MIN, CAM_ORTHO_MAX)
				_camera.size = _cam_ortho
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_ortho  = clamp(_cam_ortho + CAM_ZOOM_STEP, CAM_ORTHO_MIN, CAM_ORTHO_MAX)
				_camera.size = _cam_ortho
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if _inv_ui.visible:
						return
					_left_held = true
					var target := _ground_at_mouse()
					if Input.is_action_pressed("attack"):
						_try_attack_at(target)
					else:
						_move_target = target
						_moving = true
						_spawn_click_marker(target)
				else:
					_left_held = false
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_try_pickup_at(_ground_at_mouse())
	elif event is InputEventMouseMotion:
		if _left_held and not _inv_ui.visible and not Input.is_action_pressed("attack"):
			_move_target = _ground_at_mouse()
			_moving = true
	elif event.is_action_pressed("inventory"):
		_inv_ui.visible = !_inv_ui.visible

# ── Process loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var local_node := _get_local_player_node()

	# Câmera segue o player
	if local_node != null:
		var pp := local_node.position
		_camera.position = pp + CAM_OFFSET
		_camera.look_at(pp + Vector3(0.0, 0.5, 0.0), Vector3.UP)

		if _coords_lbl != null:
			var sv := _to_server(pp)
			_coords_lbl.text = "X: %.0f  Y: %.0f" % [sv.x, sv.y]
	else:
		if _coords_lbl != null:
			_coords_lbl.text = "X: --  Y: --"

	if not _moving or local_node == null:
		return

	var dir := _move_target - local_node.position
	dir.y = 0.0

	if dir.length() < 0.05:
		local_node.position   = _move_target
		local_node.position.y = 0.0
		_moving = false
		_broadcast_move(local_node.position)
		return

	local_node.position   += dir.normalized() * MOVE_SPEED * delta
	local_node.position.y  = 0.0

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_INTERVAL
		var pos := local_node.position
		if pos.distance_to(_last_sent) > 0.05:
			_broadcast_move(pos)
			_last_sent = pos

func _broadcast_move(pos: Vector3) -> void:
	var sv := _to_server(pos)
	WsClient.send({
		"type": "MOVE",
		"payload": {
			"x":      sv.x,
			"y":      sv.y,
			"map_id": GameState.character.get("current_map", "starter_village")
		}
	})

# ── Combate ────────────────────────────────────────────────────────────────────

func _try_attack_at(ground_pos: Vector3) -> void:
	var best_id   := ""
	var best_dist := 3.5  # units 3D
	for iid in _mobs:
		var mn = _mobs[iid]
		var d : float = Vector2(mn.position.x - ground_pos.x,
		                        mn.position.z - ground_pos.z).length()
		if d < best_dist:
			best_dist = d
			best_id   = iid
	if best_id != "":
		WsClient.send({"type": "ATTACK", "payload": {"target_id": best_id, "attack_type": "melee"}})

func _try_pickup_at(ground_pos: Vector3) -> void:
	var best_id   := ""
	var best_dist := 2.0
	for drop_id in _drops:
		var dn = _drops[drop_id]
		var d : float = Vector2(dn.position.x - ground_pos.x,
		                        dn.position.z - ground_pos.z).length()
		if d < best_dist:
			best_dist = d
			best_id   = drop_id
	if best_id != "":
		WsClient.send({"type": "PICKUP", "payload": {"drop_id": best_id}})

# ── WebSocket ──────────────────────────────────────────────────────────────────

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
		var cid   : String = p.get("character_id", "")
		var px    : float  = p.get("x", 0.0)
		var py    : float  = p.get("y", 0.0)
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
	if cid in _players:
		_players[cid].position = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))

func _handle_mob_move(payload: Dictionary) -> void:
	var iid : String = payload.get("instance_id", "")
	if iid in _mobs:
		_mobs[iid].position = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))

func _handle_player_join(payload: Dictionary) -> void:
	var cid   : String = payload.get("character_id", "")
	var pname : String = payload.get("name", "?")
	if cid not in _players:
		var node := _build_player_node(pname, Color.WHITE)
		node.position = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))
		_player_layer.add_child(node)
		_players[cid] = node

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
	var pos := _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))
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
	var new_hp  : int    = payload.get("hp",     CharacterData.hp)
	var new_mhp : int    = payload.get("max_hp", CharacterData.max_hp)
	if target == str(GameState.character.get("id", "")):
		CharacterData.apply_damage(new_hp, new_mhp)
	var pos := Vector3.ZERO
	if target in _players: pos = _players[target].position
	elif target in _mobs:  pos = _mobs[target].position
	if pos != Vector3.ZERO:
		_spawn_damage_label(pos, str(dmg))

func _handle_level_up(payload: Dictionary) -> void:
	CharacterData.apply_level_up(
		payload.get("new_level",           CharacterData.level),
		payload.get("stat_points_gained",  0),
		payload.get("skill_points_gained", 0)
	)
	CharacterData.apply_xp(
		payload.get("xp",         CharacterData.xp),
		payload.get("xp_to_next", CharacterData.xp_to_next)
	)

func _handle_map_change(payload: Dictionary) -> void:
	GameState.character["current_map"] = payload.get("map_id", "")
	GameState.character["pos_x"]       = payload.get("pos_x", 0.0)
	GameState.character["pos_y"]       = payload.get("pos_y", 0.0)
	MapManager.load_map(payload.get("map_id", ""))
	get_tree().reload_current_scene()

# ── Construtores de nó ─────────────────────────────────────────────────────────

func _make_texture(color: Color, w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _make_shadow(radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var cm   := CylinderMesh.new()
	cm.top_radius    = radius
	cm.bottom_radius = radius
	cm.height        = 0.01
	node.mesh = cm
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.32)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	node.position = Vector3(0.0, 0.005, 0.0)
	return node

func _ensure_local_player(px: float, py: float) -> void:
	var my_id := str(GameState.character.get("id", "__local__"))
	if my_id not in _players:
		var node := _build_player_node(_local_name, Color.CYAN)
		node.position = _to_3d(px, py)
		_player_layer.add_child(node)
		_players[my_id] = node

func _ensure_remote_player(cid: String, pname: String, px: float, py: float) -> void:
	if cid not in _players:
		var node := _build_player_node(pname, Color.WHITE)
		node.position = _to_3d(px, py)
		_player_layer.add_child(node)
		_players[cid] = node

func _get_local_player_node() -> Node3D:
	var my_id := str(GameState.character.get("id", "__local__"))
	return _players.get(my_id, null)

func _build_player_node(pname: String, color: Color) -> Node3D:
	var root := Node3D.new()

	# Sprite 2D billboard (placeholder até ter sprite sheet real)
	var sprite := Sprite3D.new()
	sprite.texture       = _make_texture(color, 12, 22)
	sprite.pixel_size    = 0.055
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded        = false
	sprite.no_depth_test = false
	sprite.position      = Vector3(0.0, 0.7, 0.0)
	root.add_child(sprite)

	root.add_child(_make_shadow(0.28))

	# Nome acima (Label3D billboard)
	var lbl := Label3D.new()
	lbl.text          = pname
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size     = 30
	lbl.modulate      = Color(1.0, 1.0, 0.7)
	lbl.outline_size  = 8
	lbl.no_depth_test = true
	lbl.position      = Vector3(0.0, 1.6, 0.0)
	root.add_child(lbl)

	return root

func _spawn_mob(mob: Dictionary) -> void:
	var iid : String = mob.get("instance_id", "")
	if iid in _mobs:
		return

	var root := Node3D.new()

	var sprite := Sprite3D.new()
	sprite.texture       = _make_texture(Color(0.95, 0.3, 0.3), 16, 16)
	sprite.pixel_size    = 0.055
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded        = false
	sprite.position      = Vector3(0.0, 0.55, 0.0)
	root.add_child(sprite)

	root.add_child(_make_shadow(0.32))

	var lbl := Label3D.new()
	lbl.text          = mob.get("monster_id", "mob")
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size     = 24
	lbl.modulate      = Color(1.0, 0.6, 0.6)
	lbl.outline_size  = 6
	lbl.no_depth_test = true
	lbl.position      = Vector3(0.0, 1.3, 0.0)
	root.add_child(lbl)

	root.position = _to_3d(mob.get("x", 0.0), mob.get("y", 0.0))
	_mob_layer.add_child(root)
	_mobs[iid] = root

func _build_drop_node(_drop_id: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos

	var sprite := Sprite3D.new()
	sprite.texture       = _make_texture(Color(1.0, 0.85, 0.0), 8, 8)
	sprite.pixel_size    = 0.06
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded        = false
	sprite.position      = Vector3(0.0, 0.2, 0.0)
	root.add_child(sprite)

	# Brilho no chão
	var glow := MeshInstance3D.new()
	var gm   := CylinderMesh.new()
	gm.top_radius    = 0.18
	gm.bottom_radius = 0.18
	gm.height        = 0.005
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.85, 0.0, 0.38)
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = gmat
	root.add_child(glow)

	# Bobbing do sprite
	var tw := root.create_tween()
	tw.set_loops()
	tw.tween_property(sprite, "position:y", 0.42, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sprite, "position:y", 0.20, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	return root

func _spawn_click_marker(world_pos: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var cyl    := CylinderMesh.new()
	cyl.top_radius    = 0.22
	cyl.bottom_radius = 0.22
	cyl.height        = 0.01
	marker.mesh = cyl
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	marker.position = world_pos + Vector3(0.0, 0.012, 0.0)
	add_child(marker)

	var tw := create_tween()
	tw.tween_property(marker, "scale", Vector3(4.0, 1.0, 4.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(marker.queue_free)

func _spawn_damage_label(pos: Vector3, text: String) -> void:
	var lbl := Label3D.new()
	lbl.text          = text
	lbl.position      = pos + Vector3(randf_range(-0.3, 0.3), 1.4, 0.0)
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size     = 60
	lbl.modulate      = Color(1.0, 0.88, 0.1)
	lbl.outline_size  = 12
	lbl.no_depth_test = true
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y + 2.0, 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lbl.queue_free)

# ── Desconexão ─────────────────────────────────────────────────────────────────

func _on_ws_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
