extends Node

var token: String = ""
var player_id: String = ""
var character: Dictionary = {}

func is_logged_in() -> bool:
	return token != ""

func is_character_selected() -> bool:
	return character.has("id") and character["id"] != ""

func clear() -> void:
	token = ""
	player_id = ""
	character = {}
