extends Control
## Date scene: background from the character's location, portrait swapped by the AI's emotion,
## dialogue + choices from GeminiClient. Pick a character in date_select.tscn first
## (or run this scene directly to get a random one).

const MAX_EXCHANGES := 4
var char_id := ""
var exchanges := 0
var _last_player_text := ""
@onready var _bg: TextureRect = %Background
@onready var _portrait: TextureRect = %Portrait
@onready var _speaker: Label = %Speaker
@onready var _text: RichTextLabel = %Text
@onready var _choices: HBoxContainer = %Choices
@onready var _emotion_tag: Label = %EmotionTag
@onready var _debug: Label = %DebugLabel
var _typing: Tween
var _think_dots: Tween
var _think_bob: Tween
var _portrait_home := Vector2.ZERO


func _ready() -> void:
	# Layout (positions, sizes, fonts, colors) lives in date_scene.tscn - edit it in the 2D editor.
	# This script only fills in the per-character content.
	char_id = GameState.get_meta("current_date", "") as String
	if char_id == "" or not GameState.characters.has(char_id):
		char_id = GameState.characters.keys()[randi() % GameState.characters.size()]
	_bg.texture = load(GameState.background_path(char_id))
	_set_portrait("neutral")
	_portrait_home = _portrait.position
	_portrait.pivot_offset = _portrait.size * Vector2(0.5, 1.0)   # grow/bounce from the feet
	_debug.text = "DEBUG: spy is %s" % GameState.characters[GameState.spy_id]["name"]
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/date_select.tscn"))
	GeminiClient.line_ready.connect(_on_line)
	GeminiClient.failed.connect(func(r): _debug.text = "Gemini fallback used: " + r)
	_set_loading()
	GeminiClient.request_line(char_id, _beat())


func _beat() -> String:
	return "This is a date at %s. Get to know the player, flirt a little, and let your personality show. Drop small, natural hints about yourself without revealing your secret." \
		% GameState.background_path(char_id).get_file().get_basename().replace("_", " ")


func _set_portrait(emotion: String) -> void:
	var path := GameState.portrait_path(char_id, emotion)
	if ResourceLoader.exists(path):
		_portrait.texture = load(path)


func _set_loading() -> void:
	_speaker.text = GameState.characters[char_id]["name"]
	_emotion_tag.text = ""
	for c in _choices.get_children():
		c.queue_free()
	_stop_thinking()
	# "[thinking...]" with animated dots in the dialogue box
	_text.visible_ratio = 1.0
	_think_dots = create_tween().set_loops()
	for dots in ["", ".", "..", "..."]:
		_think_dots.tween_callback(func(): _text.text = "[thinking%s]" % dots)
		_think_dots.tween_interval(0.35)
	# gentle sway on the sprite while waiting
	_think_bob = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_think_bob.tween_property(_portrait, "position:y", _portrait_home.y - 8, 0.6)
	_think_bob.tween_property(_portrait, "position:y", _portrait_home.y, 0.6)


func _stop_thinking() -> void:
	if _think_dots:
		_think_dots.kill()
	if _think_bob:
		_think_bob.kill()
	_portrait.position = _portrait_home


## Quick squash-and-pop when the character reacts to something.
func _pop_portrait() -> void:
	_portrait.scale = Vector2(1.0, 0.96)
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_portrait, "scale", Vector2(1.0, 1.0), 0.25)


func _on_line(line: Dictionary) -> void:
	_stop_thinking()
	var emotion: String = line.get("emotion", "neutral")
	_speaker.text = "%s" % line.get("speaker", GameState.characters[char_id]["name"])
	_emotion_tag.text = "   [%s]" % emotion
	_set_portrait(emotion)
	_pop_portrait()
	_text.text = line.get("text", "")
	_text.visible_ratio = 0.0
	if _typing:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, maxf(0.5, _text.text.length() * 0.02))
	_typing.finished.connect(func(): _show_choices(line.get("choices", [])))


func _show_choices(choices: Array) -> void:
	for c in _choices.get_children():
		c.queue_free()
	if exchanges >= MAX_EXCHANGES:
		var done := Button.new()
		done.text = "End date"
		done.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/date_select.tscn"))
		_choices.add_child(done)
		return
	for ch in choices:
		var b := Button.new()
		b.text = str(ch)
		b.pressed.connect(_on_choice.bind(str(ch)))
		_choices.add_child(b)


func _on_choice(text: String) -> void:
	exchanges += 1
	_last_player_text = text
	GameState.affection[char_id] += 1
	_set_loading()
	GeminiClient.request_line(char_id, _beat(), text)
