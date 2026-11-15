extends Node
## Autoload "GameState": holds the run's hidden truth. The spy is chosen HERE in code, never by the AI.

const CHARACTERS_PATH := "res://data/characters.json"

var emotions: Array = []
var characters: Dictionary = {}
var spy_id: String = ""
var day: int = 1
var dates_left: int = 5
var clues_seen: Array = []          # [{character, text}]
var memory: Dictionary = {}         # character_id -> short running summary
var player_name: String = "Johnson"
var affection: Dictionary = {}      # character_id -> int


func _ready() -> void:
	_load_characters()
	new_run()


func _load_characters() -> void:
	var f := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	emotions = data["emotions"]
	characters = data["characters"]


func new_run() -> void:
	randomize()
	var ids := characters.keys()
	spy_id = ids[randi() % ids.size()]
	day = 1
	dates_left = 5
	clues_seen.clear()
	for id in ids:
		memory[id] = ""
		affection[id] = 0


func is_spy(id: String) -> bool:
	return id == spy_id


func active_secret(id: String) -> String:
	var c: Dictionary = characters[id]
	return c["malicious_secret"] if is_spy(id) else c["innocent_secret"]


## Returns the "guess who the leaker is" result.
func accuse(id: String) -> bool:
	return is_spy(id)


func portrait_path(id: String, emotion: String) -> String:
	var c: Dictionary = characters[id]
	var p: Dictionary = c["portraits"]
	var file: String = p.get(emotion, p.get("neutral", ""))
	return c["portrait_dir"] + file


func background_path(id: String) -> String:
	return characters[id]["location"]
