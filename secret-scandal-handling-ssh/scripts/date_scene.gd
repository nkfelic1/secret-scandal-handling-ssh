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
@onready var _trust_bar: ProgressBar = %TrustBar
@onready var _trust_state: Label = %TrustState
@onready var _trust_delta: Label = %TrustDelta
var _typing: Tween
var _think_dots: Tween
var _think_bob: Tween
var _portrait_home := Vector2.ZERO
var _portrait_box := Rect2()

## Widest a portrait may get, so very wide images do not take over the screen.
const PORTRAIT_MAX_WIDTH := 900.0


func _ready() -> void:
	# Layout (positions, sizes, fonts, colors) lives in date_scene.tscn - edit it in the 2D editor.
	# This script only fills in the per-character content.
	char_id = GameState.get_meta("current_date", "") as String
	if char_id == "" or not GameState.characters.has(char_id):
		char_id = GameState.characters.keys()[randi() % GameState.characters.size()]
	_bg.texture = load(GameState.background_path(char_id))
	_portrait_box = Rect2(_portrait.position, _portrait.size)   # the box you set in the editor
	_set_portrait("neutral")
	_update_debug()
	_show_trust(0, false)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/date_select.tscn"))
	GeminiClient.line_ready.connect(_on_line)
	GeminiClient.failed.connect(func(r): _debug.text = "Gemini fallback used: " + r)
	_set_loading()
	GeminiClient.request_line(char_id, _beat())


func _beat() -> String:
	if GameState.dumped[char_id]:
		return "Johnson has been so unkind to you that you have decided to end things with him for good. Say a short, final goodbye in your own voice that reflects how he treated you. Do not ask him any questions."
	return "This is a date at %s. Get to know the player, flirt a little, and let your personality show. Drop small, natural hints about yourself without revealing your secret." \
		% GameState.background_path(char_id).get_file().get_basename().replace("_", " ")


var _visible_cache := {}


func _visible_rect(path: String, tex: Texture2D) -> Rect2i:
	if not _visible_cache.has(path):
		var r := tex.get_image().get_used_rect()
		_visible_cache[path] = r if r.size.x > 0 and r.size.y > 0 else Rect2i(0, 0, tex.get_width(), tex.get_height())
	return _visible_cache[path]


func _set_portrait(emotion: String) -> void:
	var path := GameState.portrait_path(char_id, emotion)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	# Some images have empty transparent space around the character, which made torso crops look like they
	# were floating. Show only the visible part of the image (cached per file).
	var used := _visible_rect(path, tex)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used)
	_portrait.texture = atlas
	# Scale by the full image height (so the character is the same size in every expression), keep the
	# visible part's proportions, and pin its BOTTOM edge to the bottom of the Portrait box, which sits
	# below the screen edge, so the cut-off bottom of a torso crop is never visible.
	var k := _portrait_box.size.y / float(tex.get_height())
	if used.size.x * k > PORTRAIT_MAX_WIDTH:
		k = PORTRAIT_MAX_WIDTH / float(used.size.x)
	var w := used.size.x * k
	var h := used.size.y * k
	_portrait.size = Vector2(w, h)
	_portrait.position = Vector2(_portrait_box.get_center().x - w / 2.0, _portrait_box.end.y - h)
	_portrait.pivot_offset = Vector2(w / 2.0, h)     # grow/bounce from the feet
	_portrait_home = _portrait.position


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
	if GameState.dumped[char_id] or exchanges >= MAX_EXCHANGES:
		var done := Button.new()
		done.text = "Leave" if GameState.dumped[char_id] else "End date"
		done.pressed.connect(_end_date)
		_choices.add_child(done)
		return
	for ch in choices:
		var b := Button.new()
		b.text = str(ch["text"])
		b.pressed.connect(_on_choice.bind(ch))
		_choices.add_child(b)


## GameState decides what's next: another date, the work minigame, the next day, or the ending.
func _end_date() -> void:
	GameState.finish_date(char_id)
	GameState.go_next()


func _on_choice(choice: Dictionary) -> void:
	exchanges += 1
	_last_player_text = choice["text"]
	# the hidden tone of what Johnson just said changes how much she trusts him
	var delta := GameState.apply_tone(char_id, str(choice["tone"]))
	_show_trust(delta, true)
	_update_debug()
	_set_loading()
	GeminiClient.request_line(char_id, _beat(), choice["text"], str(choice["tone"]))


func _update_debug() -> void:
	_debug.text = "DEBUG: spy is %s | trustmeter %+d" % [GameState.characters[GameState.spy_id]["name"], GameState.trustmeter]


## Updates the trust bar. With animate=true it also floats a +/- number and flashes the bar.
func _show_trust(delta: int, animate: bool) -> void:
	var t: int = GameState.trust[char_id]
	var col := Color.from_hsv(clampf(t / 100.0, 0.0, 1.0) * 0.33, 0.65, 1.0)   # red -> green
	_trust_state.text = GameState.trust_label(char_id)
	_trust_state.add_theme_color_override("font_color", col)
	_trust_bar.modulate = col
	if not animate:
		_trust_bar.value = t
		return
	create_tween().tween_property(_trust_bar, "value", float(t), 0.4).set_trans(Tween.TRANS_CUBIC)
	if delta == 0:
		return
	_trust_delta.text = "%+d" % delta
	_trust_delta.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55) if delta > 0 else Color(1.0, 0.4, 0.4))
	_trust_delta.position.y = 40.0
	_trust_delta.modulate.a = 1.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_trust_delta, "position:y", 12.0, 1.1)
	tw.tween_property(_trust_delta, "modulate:a", 0.0, 1.1).set_delay(0.4)
