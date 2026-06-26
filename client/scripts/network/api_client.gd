extends Node

# URL base do servidor — ajustar para o IP/domínio real do DonaOdete
const BASE_URL = "http://donaodete.local:7080"

func _get_headers() -> PackedStringArray:
	var headers = ["Content-Type: application/json"]
	if GameState.token != "":
		headers.append("Authorization: Bearer " + GameState.token)
	return PackedStringArray(headers)

# ── Métodos públicos ──────────────────────────────────────────────────────────

func post(path: String, body: Dictionary, callback: Callable) -> void:
	_request(HTTPClient.METHOD_POST, path, body, callback)

func get_req(path: String, callback: Callable) -> void:
	_request(HTTPClient.METHOD_GET, path, {}, callback)

func put(path: String, body: Dictionary, callback: Callable) -> void:
	_request(HTTPClient.METHOD_PUT, path, body, callback)

# ── Interno ───────────────────────────────────────────────────────────────────

func _request(method: int, path: String, body: Dictionary, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			var data = null
			if body_bytes.size() > 0:
				data = JSON.parse_string(body_bytes.get_string_from_utf8())
			callback.call(code, data)
			http.queue_free()
	)

	var body_str := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err := http.request(BASE_URL + path, _get_headers(), method, body_str)
	if err != OK:
		push_error("ApiClient: falha ao iniciar request para " + path)
		callback.call(0, null)
		http.queue_free()
