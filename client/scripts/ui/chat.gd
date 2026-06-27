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
	"battle": Color(1.0, 0.9, 0.9),
	"system": Color(1.0, 0.8, 0.3),
}
const BATTLE_COLOR := Color(1.0, 0.55, 0.3)
const XP_COLOR     := Color(0.6, 1.0, 0.6)
const DROP_COLOR   := Color(1.0, 0.85, 0.3)

const TAB_CHANNELS := ["map", "global", "party", "battle"]
const SEND_CHANNELS := ["map", "global", "party"]

var _active_channel: String = "map"
var _tab_lines: Dictionary = {}

func _ready() -> void:
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.text = ""

	for ch in TAB_CHANNELS:
		_tab_lines[ch] = []

	_chan_tabs.tab_count = 4
	_chan_tabs.set_tab_title(0, "Mapa")
	_chan_tabs.set_tab_title(1, "Global")
	_chan_tabs.set_tab_title(2, "Party")
	_chan_tabs.set_tab_title(3, "Batalha")
	_chan_tabs.tab_changed.connect(_on_tab_changed)

	_send_btn.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(func(_t): _on_send_pressed())

	WsClient.message_received.connect(_on_ws_message)

	_add_to_all("Conectado ao Aethermoor.", CHANNEL_COLORS["system"])

# ── Envio ─────────────────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	var msg := _input.text.strip_edges()
	if msg.is_empty():
		return
	_input.text = ""
	var ch := _active_channel if _active_channel in SEND_CHANNELS else "map"
	WsClient.send({
		"type": "CHAT",
		"payload": {"channel": ch, "message": msg}
	})

# ── Abas ──────────────────────────────────────────────────────────────────────

func _on_tab_changed(tab: int) -> void:
	_active_channel = TAB_CHANNELS[tab] if tab < TAB_CHANNELS.size() else "map"
	_render_active()

# ── Mensagens WS ──────────────────────────────────────────────────────────────

func _on_ws_message(type: String, payload: Dictionary) -> void:
	match type:
		"CHAT":
			var channel : String = payload.get("channel", "map")
			if channel == "local":
				channel = "map"
			var sender : String = payload.get("sender_name", "?")
			var msg    : String = payload.get("message", "")
			_add_to_tab(channel, "[%s] %s" % [sender, msg], CHANNEL_COLORS.get(channel, Color.WHITE))
		"SYSTEM":
			_add_to_all("[sistema] " + str(payload.get("message", "")), CHANNEL_COLORS["system"])
		"DAMAGE":
			if GameState.log_damage:
				_log_damage(payload)
		"XP_GAIN":
			if GameState.log_xp:
				_add_to_tab("battle", "+%d XP" % int(payload.get("gained", 0)), XP_COLOR)
		"PLAYER_DEATH":
			if GameState.log_xp:
				_add_to_tab("battle", "-%d XP (você morreu)" % int(payload.get("xp_lost", 0)), XP_COLOR)
		"DROP_PICKED":
			if GameState.log_drops and str(payload.get("picker_id", "")) == _my_id():
				var name_str : String = str(payload.get("item_name", payload.get("item_id", "item")))
				_add_to_all("Você pegou: %s" % name_str, DROP_COLOR)

func _log_damage(payload: Dictionary) -> void:
	var my := _my_id()
	var dmg  : int  = int(payload.get("damage", 0))
	var crit : bool = payload.get("is_critical", false)
	var miss : bool = payload.get("is_miss", false)
	if str(payload.get("attacker_id", "")) == my:
		if miss:
			_add_to_tab("battle", "Você errou o ataque.", BATTLE_COLOR)
		else:
			_add_to_tab("battle", "Você causou %d de dano%s" % [dmg, " (CRÍTICO!)" if crit else ""], BATTLE_COLOR)
	elif str(payload.get("target_id", "")) == my and str(payload.get("target_type", "")) == "player":
		if miss:
			_add_to_tab("battle", "Você esquivou.", BATTLE_COLOR)
		else:
			_add_to_tab("battle", "Você recebeu %d de dano." % dmg, BATTLE_COLOR)

func _my_id() -> String:
	return str(GameState.character.get("id", ""))

# ── Buffers por aba ─────────────────────────────────────────────────────────────

func _fmt(text: String, color: Color) -> String:
	var hex := "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	return "[color=%s]%s[/color]\n" % [hex, text.xml_escape()]

func _add_to_tab(ch: String, text: String, color: Color) -> void:
	if ch not in _tab_lines:
		ch = "map"
	var line := _fmt(text, color)
	var buf : Array = _tab_lines[ch]
	buf.append(line)
	if buf.size() > MAX_LINES:
		buf.remove_at(0)
	if ch == _active_channel:
		_log.append_text(line)

func _add_to_all(text: String, color: Color) -> void:
	var line := _fmt(text, color)
	for ch in _tab_lines:
		var buf : Array = _tab_lines[ch]
		buf.append(line)
		if buf.size() > MAX_LINES:
			buf.remove_at(0)
	_log.append_text(line)

func _render_active() -> void:
	_log.clear()
	for line in _tab_lines[_active_channel]:
		_log.append_text(line)

# ── Focus no Enter ────────────────────────────────────────────────────────────

func _input_focus() -> void:
	_input.grab_focus()
