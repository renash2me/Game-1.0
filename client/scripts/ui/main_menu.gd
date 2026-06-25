extends Control

@onready var _username   : LineEdit = $Center/VBox/Tabs/Login/Username
@onready var _password   : LineEdit = $Center/VBox/Tabs/Login/Password
@onready var _login_err  : Label    = $Center/VBox/Tabs/Login/Error
@onready var _reg_user   : LineEdit = $Center/VBox/Tabs/Registro/Username
@onready var _reg_email  : LineEdit = $Center/VBox/Tabs/Registro/Email
@onready var _reg_pass   : LineEdit = $Center/VBox/Tabs/Registro/Password
@onready var _reg_err    : Label    = $Center/VBox/Tabs/Registro/Error

func _ready() -> void:
	_add_background()
	GameState.clear()

func _add_background() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/sprites/login_bg.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	# Overlay escuro para os paineis ficarem legiveis
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	move_child(overlay, 1)

# ── Login ─────────────────────────────────────────────────────────────────────

func _on_login_pressed() -> void:
	var username := _username.text.strip_edges()
	var password := _password.text
	if username.is_empty() or password.is_empty():
		_login_err.text = "Preencha todos os campos."
		return
	_login_err.text = "Conectando..."

	ApiClient.post("/api/auth/login", {"username": username, "password": password}, _on_login_response)

func _on_login_response(code: int, data) -> void:
	if code == 200 and data != null:
		GameState.token = data.get("access_token", "")
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")
	else:
		var msg: String = "Erro ao fazer login."
		if data != null and data.has("detail"):
			msg = str(data["detail"])
		_login_err.text = msg

# ── Registro ──────────────────────────────────────────────────────────────────

func _on_register_pressed() -> void:
	var username := _reg_user.text.strip_edges()
	var email    := _reg_email.text.strip_edges()
	var password := _reg_pass.text
	if username.is_empty() or email.is_empty() or password.is_empty():
		_reg_err.text = "Preencha todos os campos."
		return
	_reg_err.text = "Criando conta..."
	ApiClient.post("/api/auth/register",
		{"username": username, "email": email, "password": password},
		_on_register_response)

func _on_register_response(code: int, data) -> void:
	if code == 201 and data != null:
		GameState.token = data.get("access_token", "")
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")
	else:
		var msg: String = "Erro ao criar conta."
		if data != null and data.has("detail"):
			msg = str(data["detail"])
		_reg_err.text = msg
