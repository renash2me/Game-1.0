extends Control

@onready var _username   : LineEdit = $Center/VBox/Tabs/Login/Username
@onready var _password   : LineEdit = $Center/VBox/Tabs/Login/Password
@onready var _login_err  : Label    = $Center/VBox/Tabs/Login/Error
@onready var _reg_user   : LineEdit = $Center/VBox/Tabs/Registro/Username
@onready var _reg_email  : LineEdit = $Center/VBox/Tabs/Registro/Email
@onready var _reg_pass   : LineEdit = $Center/VBox/Tabs/Registro/Password
@onready var _reg_err    : Label    = $Center/VBox/Tabs/Registro/Error

func _ready() -> void:
	GameState.clear()

# ── Login ─────────────────────────────────────────────────────────────────────

func _on_login_pressed() -> void:
	var username := _username.text.strip_edges()
	var password := _password.text
	if username.is_empty() or password.is_empty():
		_login_err.text = "Preencha todos os campos."
		return
	_login_err.text = "Conectando..."

	ApiClient.post("/api/auth/login", {"username": username, "password": password},
		func(code: int, data):
			if code == 200 and data != null:
				GameState.token = data.get("access_token", "")
				get_tree().change_scene_to_file("res://scenes/character_select.tscn")
			else:
				var msg: String = "Erro ao fazer login."
				if data != null and data.has("detail"):
					msg = str(data["detail"])
				_login_err.text = msg
	)

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
		func(code: int, data):
			if code == 201 and data != null:
				GameState.token = data.get("access_token", "")
				get_tree().change_scene_to_file("res://scenes/character_select.tscn")
			else:
				var msg: String = "Erro ao criar conta."
				if data != null and data.has("detail"):
					msg = str(data["detail"])
				_reg_err.text = msg
	)
