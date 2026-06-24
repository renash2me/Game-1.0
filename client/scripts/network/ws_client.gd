extends Node

signal message_received(type: String, payload: Dictionary)
signal ws_connected
signal ws_disconnected

const WS_URL = "ws://donaodete.local:7080/ws"
const RECONNECT_DELAY = 3.0

var _socket: WebSocketPeer = null
var _connected: bool = false
var _auth_ok: bool = false
var _reconnect_timer: float = 0.0
var _should_reconnect: bool = false
var _pending_character_id: String = ""

# ── API pública ───────────────────────────────────────────────────────────────

func authenticate(character_id: String) -> void:
	_pending_character_id = character_id
	_should_reconnect = true
	_open_socket()

func send(data: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(data))

func disconnect_ws() -> void:
	_should_reconnect = false
	_auth_ok = false
	if _socket:
		_socket.close()
		_socket = null
	_connected = false

# ── Loop ──────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _reconnect_timer > 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_open_socket()
		return

	if _socket == null:
		return

	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_auth_ok = false
				_send_auth()
			_poll_messages()

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				_auth_ok = false
				ws_disconnected.emit()
			if _should_reconnect:
				_reconnect_timer = RECONNECT_DELAY

# ── Interno ───────────────────────────────────────────────────────────────────

func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(WS_URL)
	if err != OK:
		push_error("WsClient: não foi possível conectar em " + WS_URL)
		if _should_reconnect:
			_reconnect_timer = RECONNECT_DELAY

func _send_auth() -> void:
	send({
		"type": "AUTH",
		"payload": {
			"token": GameState.token,
			"character_id": _pending_character_id
		}
	})

func _poll_messages() -> void:
	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet().get_string_from_utf8()
		var msg = JSON.parse_string(raw)
		if msg == null:
			continue

		var type: String = msg.get("type", "")
		var payload: Dictionary = msg.get("payload", {})

		if type == "AUTH_OK":
			_auth_ok = true
			# Atualiza posição inicial do personagem
			GameState.character["current_map"] = payload.get("map_id", "starter_village")
			GameState.character["pos_x"] = payload.get("pos_x", 0.0)
			GameState.character["pos_y"] = payload.get("pos_y", 0.0)
			ws_connected.emit()

		message_received.emit(type, payload)
