extends Node

signal map_changed(map_id: String)

var current_map_id: String = ""

func load_map(map_id: String) -> void:
	if current_map_id == map_id:
		return
	current_map_id = map_id
	GameState.character["current_map"] = map_id
	map_changed.emit(map_id)
	# Futuramente: carregar assets do mapa (tileset, música, etc.)
