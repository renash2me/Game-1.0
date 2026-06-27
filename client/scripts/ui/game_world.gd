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
const GRID_SERVER   : float  = 40.0              # lado da célula (server units) — movimento estilo Ragnarok
const REMOTE_SMOOTH : float  = 12.0              # suavização de mobs/jogadores remotos (updates discretos)
const ATTACK_RANGE  : float  = 1.4               # 3D units (~56 server) p/ atacar o mob travado
const ATTACK_INTERVAL : float = 1.0              # segundos entre auto-ataques

# ── Referências ────────────────────────────────────────────────────────────────
@onready var _player_layer : Node3D     = $Layers/Players
@onready var _mob_layer    : Node3D     = $Layers/Mobs
@onready var _drop_layer   : Node3D     = $Layers/Drops
@onready var _camera       : Camera3D   = $Camera3D
@onready var _hud          : CanvasLayer = $HUD
@onready var _inv_ui       : Control    = $HUD/Inventory

# ── Estado ─────────────────────────────────────────────────────────────────────
var _local_name  : String  = ""
var _map_display : String  = ""
var _coords_lbl           = null
var _cam_ortho   : float   = CAM_ORTHO_DEF
var _path        : Array[Vector3] = []   # waypoints (centros de célula) até o destino
var _left_held   : bool    = false
var _drag_to_move : bool   = false       # o hold atual deve arrastar-mover? (false se clicou num mob)
var _target_mob  : String  = ""          # mob travado para auto-attack (persegue e ataca sozinho)
var _attack_cd   : float   = 0.0         # tempo restante até o próximo auto-ataque
var _attack_interval : float = ATTACK_INTERVAL   # intervalo entre ataques (derivado do aspd)
var _sitting     : bool    = false       # sentado? (regenera HP/SP mais rápido — tecla Insert)
var _dead        : bool    = false       # morto? (bloqueia ações até renascer)
var _death_layer : CanvasLayer = null
var _death_xp_lbl          = null
var _respawn_btn           = null
var _menu_layer  : CanvasLayer = null    # menu do Esc (voltar à seleção / deslogar)
var _dest_cell   : Vector2i = Vector2i(0x7fffffff, 0x7fffffff)  # última célula de destino (evita recalcular no drag)
var _mob_dest    : Dictionary = {}        # instance_id -> Vector3 alvo (suavização de movimento)
var _remote_dest : Dictionary = {}        # character_id -> Vector3 alvo (suavização de movimento)
var _players     : Dictionary = {}
var _mobs        : Dictionary = {}
var _drops       : Dictionary = {}

# ── Inicialização ──────────────────────────────────────────────────────────────

func _ready() -> void:
	_local_name = str(GameState.character.get("name", ""))
	_map_display = str(GameState.character.get("current_map", "starter_village")).capitalize()
	CharacterData.apply_from_response(GameState.character)

	# Velocidade de ataque vem das fórmulas (campo derived.aspd)
	var derived = GameState.character.get("derived", {})
	if derived is Dictionary:
		var aspd : float = derived.get("aspd", 1.0)
		_attack_interval = 1.0 / max(0.2, aspd)

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
	_ensure_local_player(px, py)

	_build_death_ui()
	_build_menu_ui()
	_hud.add_child(load("res://scripts/ui/hotbar.gd").new())   # barra de ação

	WsClient.message_received.connect(_on_ws_message)
	WsClient.ws_disconnected.connect(_on_ws_disconnected)
	MapManager.load_map(GameState.character.get("current_map", "starter_village"))
	# Pede o estado do mapa agora que já estamos escutando (o MOB_SPAWN do login
	# chega antes desta cena carregar e se perde — sem isto, mobs só aparecem
	# quando algo os reenvia, ex.: respawn pelo admin).
	WsClient.send({"type": "REQUEST_MAP_STATE", "payload": {}})

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
	# Topo-direito, alinhado à direita
	_coords_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coords_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_coords_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coords_lbl.offset_left   = -320.0
	_coords_lbl.offset_right  = -10.0
	_coords_lbl.offset_top    = 8.0
	_coords_lbl.offset_bottom = 48.0

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
	var hit    = ground.intersects_ray(origin, Vector3(0.0, -0.80420, -0.59441))
	if hit == null:
		return Vector3.ZERO
	return hit

# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_menu()
		get_viewport().set_input_as_handled()
		return
	if _dead:
		return   # morto: nenhuma ação até renascer
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
					_left_held = true
					_stand_up()   # agir levanta o personagem
					var target := _ground_at_mouse()
					# Prioridade: pegar drop > atacar mob > andar
					var drop_id := _drop_at(target)
					if drop_id != "":
						_drag_to_move = false
						_target_mob   = ""
						WsClient.send({"type": "PICKUP", "payload": {"drop_id": drop_id}})
					elif _mob_at(target) != "":
						# Trava o alvo: persegue e ataca sozinho até matar ou clicar fora
						_drag_to_move = false
						_target_mob   = _mob_at(target)
						_attack_cd    = 0.0
						_path.clear()
					else:
						_drag_to_move = true
						_target_mob   = ""
						_set_destination(target)
				else:
					_left_held    = false
					_drag_to_move = false
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_try_pickup_at(_ground_at_mouse())
	elif event is InputEventMouseMotion:
		if _left_held and _drag_to_move:
			_set_destination(_ground_at_mouse())
	elif event.is_action_pressed("inventory"):
		_inv_ui.visible = !_inv_ui.visible
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_INSERT:
		_toggle_sit()   # sentar/levantar (regenera HP/SP mais rápido sentado)
		get_viewport().set_input_as_handled()

# ── Sentar / levantar ───────────────────────────────────────────────────────────

func _toggle_sit() -> void:
	_sitting = not _sitting
	WsClient.send({"type": "SIT", "payload": {"sitting": _sitting}})

func _stand_up() -> void:
	if _sitting:
		_sitting = false
		WsClient.send({"type": "SIT", "payload": {"sitting": false}})

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
			_coords_lbl.text = "%s\nX: %.0f   Y: %.0f" % [_map_display, sv.x, sv.y]
	else:
		if _coords_lbl != null:
			_coords_lbl.text = "%s\nX: --   Y: --" % _map_display

	if _dead:
		_smooth_others(delta)   # morto: sem movimento/ataque, mundo continua
		return

	# Auto-attack: persegue e ataca o mob travado (estilo Ragnarok)
	if _target_mob != "" and local_node != null:
		if _target_mob in _mobs:
			var mob_node = _mobs[_target_mob]
			var to_mob : Vector3 = mob_node.position - local_node.position
			to_mob.y = 0.0
			if to_mob.length() <= ATTACK_RANGE:
				_path.clear()                       # no alcance: para e ataca
				_attack_cd -= delta
				if _attack_cd <= 0.0:
					_attack_cd = _attack_interval
					_attack_mob(_target_mob)
			else:
				if _path.is_empty():
					_dest_cell = Vector2i(0x7fffffff, 0x7fffffff)  # força recalcular a rota
				_set_destination(mob_node.position, false)         # persegue, sem marcador
		else:
			_target_mob = ""    # mob morreu ou saiu de vista

	# Movimento local: caminha célula a célula até esvaziar o caminho
	if local_node != null and not _path.is_empty():
		var target : Vector3 = _path[0]
		var dir := target - local_node.position
		dir.y = 0.0
		var step := MOVE_SPEED * delta
		if dir.length() <= step:
			local_node.position = Vector3(target.x, 0.0, target.z)
			_path.remove_at(0)
			_broadcast_move(local_node.position)   # avisa servidor ao chegar em cada célula
		else:
			local_node.position   += dir.normalized() * step
			local_node.position.y  = 0.0

	# Mobs e jogadores remotos recebem updates discretos → suaviza a interpolação
	_smooth_others(delta)

# ── Movimento em grade (estilo Ragnarok) ────────────────────────────────────────

func _set_destination(world_point: Vector3, show_marker: bool = true) -> void:
	var local_node := _get_local_player_node()
	if local_node == null:
		return
	var goal := _server_to_cell(_to_server(world_point))
	if goal == _dest_cell:
		return   # mesmo destino: não recalcula (evita reconstruir o caminho a cada pixel no drag)
	_dest_cell = goal
	var start := _server_to_cell(_to_server(local_node.position))
	_path = _build_path(start, goal)
	if show_marker and not _path.is_empty():
		_spawn_click_marker(_path[_path.size() - 1])

func _server_to_cell(sv: Vector2) -> Vector2i:
	return Vector2i(roundi(sv.x / GRID_SERVER), roundi(sv.y / GRID_SERVER))

func _cell_to_3d(cell: Vector2i) -> Vector3:
	return _to_3d(float(cell.x) * GRID_SERVER, float(cell.y) * GRID_SERVER)

func _build_path(start: Vector2i, goal: Vector2i) -> Array[Vector3]:
	# Passos em 8 direções (Chebyshev): anda na diagonal até alinhar, depois reto.
	# Sem obstáculos no mapa plano, isso equivale ao caminho ótimo (A* seria exagero).
	var pts : Array[Vector3] = []
	var cur := start
	var guard := 0
	while cur != goal and guard < 512:
		guard += 1
		cur.x += signi(goal.x - cur.x)
		cur.y += signi(goal.y - cur.y)
		pts.append(_cell_to_3d(cur))
	return pts

func _smooth_others(delta: float) -> void:
	var t := clampf(delta * REMOTE_SMOOTH, 0.0, 1.0)
	for iid in _mob_dest:
		if iid in _mobs:
			var d : Vector3 = _mob_dest[iid]
			_mobs[iid].position = _mobs[iid].position.lerp(d, t)
	for cid in _remote_dest:
		if cid in _players:
			var d : Vector3 = _remote_dest[cid]
			_players[cid].position = _players[cid].position.lerp(d, t)

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

func _mob_at(ground_pos: Vector3) -> String:
	var best_id   := ""
	var best_dist := 0.7  # ~28 server units: raio de clique sobre o monstro
	for iid in _mobs:
		var mn = _mobs[iid]
		var d : float = Vector2(mn.position.x - ground_pos.x,
		                        mn.position.z - ground_pos.z).length()
		if d < best_dist:
			best_dist = d
			best_id   = iid
	return best_id

func _attack_mob(mob_id: String) -> void:
	WsClient.send({"type": "ATTACK", "payload": {"target_id": mob_id, "attack_type": "melee"}})

func _drop_at(ground_pos: Vector3) -> String:
	var best_id   := ""
	var best_dist := 0.8   # raio de clique sobre o drop (~32 server units)
	for drop_id in _drops:
		var dn = _drops[drop_id]
		var d : float = Vector2(dn.position.x - ground_pos.x,
		                        dn.position.z - ground_pos.z).length()
		if d < best_dist:
			best_dist = d
			best_id   = drop_id
	return best_id

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
		"MOB_CLEAR":    _handle_mob_clear(payload)
		"DROP_APPEAR":  _handle_drop_appear(payload)
		"DROP_PICKED":  _handle_drop_taken(payload)
		"DROP_TAKEN":   _handle_drop_taken(payload)
		"DAMAGE":       _handle_damage(payload)
		"STATS_UPDATE": _handle_stats_update(payload)
		"XP_GAIN":      _handle_xp_gain(payload)
		"LEVEL_UP":     _handle_level_up(payload)
		"PLAYER_DEATH": _handle_player_death(payload)
		"RESPAWN_OK":   _handle_respawn_ok(payload)
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

func _handle_mob_clear(_payload: Dictionary) -> void:
	# Re-spawn ao vivo (admin): remove todos os mobs antes de receber os novos
	for iid in _mobs:
		_mobs[iid].queue_free()
	_mobs.clear()
	_mob_dest.clear()
	_target_mob = ""

func _handle_player_move(payload: Dictionary) -> void:
	var cid : String = payload.get("character_id", "")
	# guarda só o alvo; a interpolação acontece em _smooth_others (não teleporta)
	if cid in _players and cid != str(GameState.character.get("id", "")):
		_remote_dest[cid] = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))

func _handle_mob_move(payload: Dictionary) -> void:
	var iid : String = payload.get("instance_id", "")
	if iid in _mobs:
		_mob_dest[iid] = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))

func _handle_player_join(payload: Dictionary) -> void:
	var cid   : String = payload.get("character_id", "")
	var pname : String = payload.get("name", "?")
	if cid not in _players:
		var node := _build_player_node(pname, Color.WHITE)
		node.position = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))
		_player_layer.add_child(node)
		_players[cid] = node
		_remote_dest[cid] = node.position

func _handle_player_leave(payload: Dictionary) -> void:
	var cid : String = payload.get("character_id", "")
	if cid in _players:
		_players[cid].queue_free()
		_players.erase(cid)
		_remote_dest.erase(cid)

func _handle_mob_death(payload: Dictionary) -> void:
	var iid : String = payload.get("instance_id", "")
	if iid in _mobs:
		_mobs[iid].queue_free()
		_mobs.erase(iid)
		_mob_dest.erase(iid)
	if iid == _target_mob:
		_target_mob = ""
	# Os drops vêm dentro do MOB_DEATH — renderiza cada um no chão
	for drop in payload.get("drops", []):
		_spawn_drop(drop)

func _handle_drop_appear(payload: Dictionary) -> void:
	# Mensagem avulsa (ex.: drops já no chão ao entrar no mapa)
	_spawn_drop(payload)

func _spawn_drop(drop: Dictionary) -> void:
	var drop_id : String = drop.get("drop_id", "")
	if drop_id == "" or drop_id in _drops:
		return
	var pos := _to_3d(drop.get("x", 0.0), drop.get("y", 0.0))
	var node := _build_drop_node(drop_id, pos)
	_drop_layer.add_child(node)
	_drops[drop_id] = node
	# Some sozinho ao expirar (ttl em segundos vindo do servidor)
	var ttl : float = drop.get("ttl", 15.0)
	get_tree().create_timer(ttl).timeout.connect(_expire_drop.bind(drop_id))

func _expire_drop(drop_id: String) -> void:
	if drop_id in _drops:
		_drops[drop_id].queue_free()
		_drops.erase(drop_id)

func _handle_drop_taken(payload: Dictionary) -> void:
	var drop_id : String = payload.get("drop_id", "")
	if drop_id in _drops:
		_drops[drop_id].queue_free()
		_drops.erase(drop_id)

func _handle_damage(payload: Dictionary) -> void:
	# O servidor envia target_id / target_type / target_hp / target_hp_max
	var target_id : String = payload.get("target_id", "")
	var ttype     : String = payload.get("target_type", "")
	var is_miss   : bool   = payload.get("is_miss", false)
	var dmg       : int    = payload.get("damage", 0)
	var new_hp    : int    = payload.get("target_hp",     CharacterData.hp)
	var new_mhp   : int    = payload.get("target_hp_max", CharacterData.max_hp)

	# Atualiza o HP do jogador local quando ele é o alvo
	if ttype == "player" and target_id == str(GameState.character.get("id", "")):
		CharacterData.apply_damage(new_hp, new_mhp)

	# Número de dano flutuante sobre o alvo (jogador ou mob)
	var node = _players.get(target_id, null)
	if node == null:
		node = _mobs.get(target_id, null)
	if node != null:
		_spawn_damage_label(node.position, "Miss" if is_miss else str(dmg))

func _handle_stats_update(payload: Dictionary) -> void:
	CharacterData.apply_damage(payload.get("hp", CharacterData.hp), payload.get("hp_max", CharacterData.max_hp))
	CharacterData.apply_sp(payload.get("sp", CharacterData.sp), payload.get("sp_max", CharacterData.max_sp))

# ── Menu (Esc) ──────────────────────────────────────────────────────────────────

func _build_menu_ui() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 101
	add_child(_menu_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	var btn_resume := Button.new()
	btn_resume.text = "Continuar"
	btn_resume.custom_minimum_size = Vector2(260, 38)
	btn_resume.pressed.connect(_toggle_menu)
	vb.add_child(btn_resume)

	var btn_select := Button.new()
	btn_select.text = "Voltar à seleção de personagem"
	btn_select.custom_minimum_size = Vector2(260, 38)
	btn_select.pressed.connect(_on_back_to_select)
	vb.add_child(btn_select)

	# Configurações de log (abre/fecha os toggles)
	var log_box := VBoxContainer.new()
	log_box.visible = false
	var btn_logcfg := Button.new()
	btn_logcfg.text = "Configurações de log"
	btn_logcfg.custom_minimum_size = Vector2(260, 38)
	btn_logcfg.pressed.connect(func(): log_box.visible = not log_box.visible)
	vb.add_child(btn_logcfg)
	vb.add_child(log_box)

	var cb_dmg := CheckButton.new()
	cb_dmg.text = "Log de dano (causado/recebido)"
	cb_dmg.button_pressed = GameState.log_damage
	cb_dmg.toggled.connect(func(on): _set_log("damage", on))
	log_box.add_child(cb_dmg)

	var cb_xp := CheckButton.new()
	cb_xp.text = "Log de XP (ganho/perdido)"
	cb_xp.button_pressed = GameState.log_xp
	cb_xp.toggled.connect(func(on): _set_log("xp", on))
	log_box.add_child(cb_xp)

	var cb_drop := CheckButton.new()
	cb_drop.text = "Log de drops pegos"
	cb_drop.button_pressed = GameState.log_drops
	cb_drop.toggled.connect(func(on): _set_log("drops", on))
	log_box.add_child(cb_drop)

	var btn_logout := Button.new()
	btn_logout.text = "Deslogar"
	btn_logout.custom_minimum_size = Vector2(260, 38)
	btn_logout.modulate = Color(1.0, 0.7, 0.7)
	btn_logout.pressed.connect(_on_logout)
	vb.add_child(btn_logout)

	_menu_layer.visible = false

func _set_log(key: String, on: bool) -> void:
	match key:
		"damage": GameState.log_damage = on
		"xp":     GameState.log_xp = on
		"drops":  GameState.log_drops = on
	GameState.save_log_settings()

func _toggle_menu() -> void:
	if _menu_layer != null:
		_menu_layer.visible = not _menu_layer.visible

func _on_back_to_select() -> void:
	WsClient.disconnect_ws()
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_logout() -> void:
	WsClient.disconnect_ws()
	GameState.clear()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ── Morte / Renascimento ────────────────────────────────────────────────────────

func _build_death_ui() -> void:
	_death_layer = CanvasLayer.new()
	_death_layer.layer = 100
	add_child(_death_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_death_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_layer.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Você morreu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(1.0, 0.4, 0.4)
	vb.add_child(title)

	_death_xp_lbl = Label.new()
	_death_xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_xp_lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(_death_xp_lbl)

	_respawn_btn = Button.new()
	_respawn_btn.text = "Voltar ao ponto de início"
	_respawn_btn.custom_minimum_size = Vector2(0, 40)
	_respawn_btn.pressed.connect(_on_respawn_pressed)
	vb.add_child(_respawn_btn)

	_death_layer.visible = false

func _handle_player_death(payload: Dictionary) -> void:
	_dead = true
	_target_mob = ""
	_path.clear()
	_sitting = false
	var lost : int = payload.get("xp_lost", 0)
	if _death_xp_lbl != null:
		_death_xp_lbl.text = "Você perdeu %d de XP." % lost
	if _respawn_btn != null:
		_respawn_btn.disabled = false
	if _death_layer != null:
		_death_layer.visible = true

func _on_respawn_pressed() -> void:
	if _respawn_btn != null:
		_respawn_btn.disabled = true   # evita clique duplo até o servidor responder
	WsClient.send({"type": "RESPAWN", "payload": {}})

func _handle_respawn_ok(payload: Dictionary) -> void:
	_dead = false
	if _death_layer != null:
		_death_layer.visible = false
	_path.clear()
	_target_mob = ""
	_dest_cell = Vector2i(0x7fffffff, 0x7fffffff)
	var node := _get_local_player_node()
	if node != null:
		node.position = _to_3d(payload.get("x", 0.0), payload.get("y", 0.0))
	CharacterData.apply_damage(payload.get("hp", CharacterData.max_hp), payload.get("hp_max", CharacterData.max_hp))
	CharacterData.apply_sp(payload.get("sp", CharacterData.max_sp), payload.get("sp_max", CharacterData.max_sp))

func _handle_xp_gain(payload: Dictionary) -> void:
	CharacterData.apply_xp(
		payload.get("xp",         CharacterData.xp),
		payload.get("xp_to_next", CharacterData.xp_to_next)
	)

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
	# Subir de nível restaura HP/SP 100% no novo máximo
	if payload.has("hp_max"):
		CharacterData.apply_damage(payload.get("hp", CharacterData.max_hp), payload.get("hp_max", CharacterData.max_hp))
	if payload.has("sp_max"):
		CharacterData.apply_sp(payload.get("sp", CharacterData.max_sp), payload.get("sp_max", CharacterData.max_sp))

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
		_remote_dest[cid] = node.position

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

	var aggressive : bool = mob.get("ai_type", "passive") == "aggressive"
	var body_color := Color(0.85, 0.2, 0.2) if aggressive else Color(1.0, 0.55, 0.65)
	var name_color := Color(1.0, 0.45, 0.35) if aggressive else Color(0.85, 0.95, 0.85)

	var root := Node3D.new()

	var sprite := Sprite3D.new()
	sprite.texture       = _make_texture(body_color, 16, 16)
	sprite.pixel_size    = 0.055
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded        = false
	sprite.position      = Vector3(0.0, 0.55, 0.0)
	root.add_child(sprite)

	root.add_child(_make_shadow(0.32))

	var lbl := Label3D.new()
	lbl.text          = mob.get("name", mob.get("mob_id", "mob"))
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size     = 24
	lbl.modulate      = name_color
	lbl.outline_size  = 6
	lbl.no_depth_test = true
	lbl.position      = Vector3(0.0, 1.3, 0.0)
	root.add_child(lbl)

	root.position = _to_3d(mob.get("x", 0.0), mob.get("y", 0.0))
	_mob_layer.add_child(root)
	_mobs[iid] = root
	_mob_dest[iid] = root.position

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
