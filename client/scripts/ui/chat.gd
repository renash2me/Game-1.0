extends Control

@onready var _log       : RichTextLabel = $VBox/Log
@onready var _input     : LineEdit      = $VBox/InputRow/Input
@onready var _send_btn  : Button        = $VBox/InputRow/Send
@onready var _chan_tabs  : TabBar        = $VBox/Channels

const MAX_LINES := 200
const CHANNEL_COLORS := {
	"map":    Color(0.9, 0.9, 0.9),
	"global": Color(0.6, 1.0, 0.6),
	"party":  Color(0.5, 0.8, 1.0),
	"system": Color(1.0, 0.8, 0.3),
}

var _active_channel: String = "map"

func _ready() -> void:
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.text = ""

	_chan_tabs.tab_count = 3
	_chan_tabs.set_tab_title(0, "Mapa")
	_chan_tabs.set_tab_title(1, "Global")
	_chan_tabs.set_tab_title(2, "Party")
	_chan_tabs.tab_changed.connect(_on_tab_changed)

	_send_btn.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(func(_t): _on_send_pressed())

	WsClient.message_received.connect(_on_ws_message)

	_add_system_line("Conectado ao Aethermoor.")

# ── Envio ─────────────────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	var msg := _input.text.strip_edges()
	if msg.is_empty():
		return
	_input.text = ""

	WsClient.send({
		"type": "CHAT",
		"payload": {"channel": _active_channel, "message": msg}
	})

	# Exibe a própria mensagem localmente (servidor não faz echo para o remetente em canal local/map)
	var my_name : String = GameState.character.get("name", "Eu")
	_add_line(_active_channel, "[%s] %s" % [my_name, msg])

# ── Canal ─────────────────────────────────────────────────────────────────────

func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _active_channel = "map"
		1: _active_channel = "global"
		2: _active_channel = "party"

# ── Mensagens WS ──────────────────────────────────────────────────────────────

func _on_ws_message(type: String, payload: Dictionary) -> void:
	if type == "CHAT":
		var channel : String = payload.get("channel", "map")
		var sender  : String = payload.get("sender_name", "?")
		var msg     : String = payload.get("message", "")
		_add_line(channel, "[%s] %s" % [sender, msg])
	elif type == "SYSTEM":
		_add_system_line(payload.get("message", ""))

func _add_system_line(msg: String) -> void:
	_add_line("system", "[sistema] " + msg)

func _add_line(channel: String, text: String) -> void:
	var color: Color = CHANNEL_COLORS.get(channel, Color.WHITE)
	var hex := "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	_log.append_text("[color=%s]%s[/color]\n" % [hex, text.xml_escape()])
	_trim_log()

func _trim_log() -> void:
	var lines := _log.text.split("\n")
	if lines.size() > MAX_LINES:
		_log.clear()
		_log.text = "\n".join(lines.slice(lines.size() - MAX_LINES))

# ── Focus no Enter ────────────────────────────────────────────────────────────

func _input_focus() -> void:
	_input.grab_focus()
