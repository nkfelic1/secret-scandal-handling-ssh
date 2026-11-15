extends Control

## Date scene:
## Shows the selected character, Gemini dialogue,
## Johnson's selected response, choices and trust.
##
## When Johnson speaks, his dialogue types at the same time
## Gemini generates the woman's response.
##
## The woman's response is not displayed until BOTH:
## 1. Johnson's text has completely finished typing.
## 2. Gemini has finished generating the response.

const MAX_EXCHANGES := 4
const PORTRAIT_MAX_WIDTH := 900.0

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

var _visible_cache := {}


# --------------------------------------------------
# RESPONSE WAITING STATE
# --------------------------------------------------

# True while Johnson is currently saying
# one of the player's selected choices.
var _johnson_speaking: bool = false

# Becomes true when Johnson's typewriter animation finishes.
var _johnson_text_finished: bool = false

# Stores Gemini's response if Gemini finishes before
# Johnson finishes typing.
var _pending_response: Dictionary = {}

# True once Gemini has returned a response.
var _response_ready: bool = false


func _ready() -> void:
	char_id = GameState.get_meta(
		"current_date",
		""
	) as String

	if (
		char_id == ""
		or not GameState.characters.has(char_id)
	):
		var keys := GameState.characters.keys()

		char_id = keys[
			randi() % keys.size()
		]

	# A woman Johnson wrongly accused of leaking will never date him again.
	if GameState.is_accused(char_id):
		get_tree().change_scene_to_file.call_deferred(
			GameState.DATE_SELECT_SCENE
		)
		return

	# --------------------------------------------------
	# Background
	# --------------------------------------------------

	var background_path: String = (
		GameState.background_path(char_id)
	)

	if ResourceLoader.exists(background_path):
		_bg.texture = load(background_path)
	else:
		push_error(
			"Background does not exist: "
			+ background_path
		)

	# --------------------------------------------------
	# Portrait
	# --------------------------------------------------

	_portrait_box = Rect2(
		_portrait.position,
		_portrait.size
	)

	_set_portrait("neutral")

	# --------------------------------------------------
	# UI
	# --------------------------------------------------

	_update_debug()
	_show_trust(0, false)

	%BackButton.pressed.connect(
		func():
			get_tree().change_scene_to_file(
				"res://scenes/date_select.tscn"
			)
	)

	# --------------------------------------------------
	# Gemini
	# --------------------------------------------------

	if not GeminiClient.line_ready.is_connected(_on_line):
		GeminiClient.line_ready.connect(_on_line)

	GeminiClient.failed.connect(
		func(reason):
			_debug.text = (
				"Gemini fallback used: "
				+ str(reason)
			)
	)

	# Initial character response.
	_set_loading()

	GeminiClient.request_line(
		char_id,
		_beat()
	)


func _beat() -> String:
	if GameState.dumped[char_id]:
		return (
			"Johnson has been so unkind to you that you have decided "
			+ "to end things with him for good. Say a short, final "
			+ "goodbye in your own voice that reflects how he treated "
			+ "you. Do not ask him any questions."
		)

	return (
		"This is a date at %s. Get to know the player, flirt a little, "
		+ "and let your personality show. Drop small, natural hints "
		+ "about yourself without revealing your secret."
	) % GameState.background_path(
		char_id
	).get_file().get_basename().replace(
		"_",
		" "
	)


# --------------------------------------------------
# PORTRAIT
# --------------------------------------------------

func _visible_rect(
	path: String,
	texture: Texture2D
) -> Rect2i:

	if not _visible_cache.has(path):
		var rect := (
			texture
			.get_image()
			.get_used_rect()
		)

		if rect.size.x > 0 and rect.size.y > 0:
			_visible_cache[path] = rect
		else:
			_visible_cache[path] = Rect2i(
				0,
				0,
				texture.get_width(),
				texture.get_height()
			)

	return _visible_cache[path]


func _set_portrait(emotion: String) -> void:
	var path: String = GameState.portrait_path(
		char_id,
		emotion
	)

	if not ResourceLoader.exists(path):
		return

	var texture: Texture2D = load(path)

	var used: Rect2i = _visible_rect(
		path,
		texture
	)

	var atlas := AtlasTexture.new()

	atlas.atlas = texture
	atlas.region = Rect2(used)

	_portrait.texture = atlas

	var scale_amount: float = (
		_portrait_box.size.y
		/ float(texture.get_height())
	)

	if (
		used.size.x * scale_amount
		> PORTRAIT_MAX_WIDTH
	):
		scale_amount = (
			PORTRAIT_MAX_WIDTH
			/ float(used.size.x)
		)

	var width: float = (
		used.size.x
		* scale_amount
	)

	var height: float = (
		used.size.y
		* scale_amount
	)

	_portrait.size = Vector2(
		width,
		height
	)

	_portrait.position = Vector2(
		_portrait_box.get_center().x
		- width / 2.0,

		_portrait_box.end.y
		- height
	)

	_portrait.pivot_offset = Vector2(
		width / 2.0,
		height
	)

	_portrait_home = _portrait.position


# --------------------------------------------------
# THINKING / LOADING
# --------------------------------------------------

func _set_loading() -> void:
	_speaker.text = (
		GameState.characters[
			char_id
		]["name"]
	)

	_emotion_tag.text = ""

	for child in _choices.get_children():
		child.queue_free()

	_stop_thinking()

	_text.visible_ratio = 1.0

	# Animated "[thinking...]"
	_think_dots = (
		create_tween()
		.set_loops()
	)

	for dots in ["", ".", "..", "..."]:
		_think_dots.tween_callback(
			func():
				_text.text = (
					"[thinking%s]" % dots
				)
		)

		_think_dots.tween_interval(
			0.35
		)

	# Gentle portrait sway while waiting.
	_think_bob = (
		create_tween()
		.set_loops()
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN_OUT)
	)

	_think_bob.tween_property(
		_portrait,
		"position:y",
		_portrait_home.y - 8,
		0.6
	)

	_think_bob.tween_property(
		_portrait,
		"position:y",
		_portrait_home.y,
		0.6
	)


func _stop_thinking() -> void:
	if _think_dots:
		_think_dots.kill()
		_think_dots = null

	if _think_bob:
		_think_bob.kill()
		_think_bob = null

	_portrait.position = _portrait_home


func _pop_portrait() -> void:
	_portrait.scale = Vector2(
		1.0,
		0.96
	)

	var tween := (
		create_tween()
		.set_trans(Tween.TRANS_BACK)
		.set_ease(Tween.EASE_OUT)
	)

	tween.tween_property(
		_portrait,
		"scale",
		Vector2.ONE,
		0.25
	)


# --------------------------------------------------
# GEMINI RESPONSE
# --------------------------------------------------

func _on_line(line: Dictionary) -> void:
	# --------------------------------------------------
	# Johnson is currently speaking.
	#
	# Don't immediately display Gemini's response.
	# Save it until Johnson finishes typing.
	# --------------------------------------------------

	if _johnson_speaking:
		_pending_response = line.duplicate(true)
		_response_ready = true

		_try_show_pending_response()

		return

	# --------------------------------------------------
	# Normal response, such as the first line of the date.
	# --------------------------------------------------

	_display_character_line(line)


func _try_show_pending_response() -> void:
	# We need BOTH conditions:
	#
	# Johnson finished typing
	# AND
	# Gemini finished generating.

	if not _johnson_text_finished:
		return

	if not _response_ready:
		return

	var response: Dictionary = (
		_pending_response.duplicate(true)
	)

	# Reset state before displaying it.
	_johnson_speaking = false
	_johnson_text_finished = false
	_response_ready = false
	_pending_response.clear()

	_display_character_line(response)


func _display_character_line(
	line: Dictionary
) -> void:

	_stop_thinking()

	var emotion: String = str(
		line.get(
			"emotion",
			"neutral"
		)
	)

	_speaker.text = str(
		line.get(
			"speaker",
			GameState.characters[
				char_id
			]["name"]
		)
	)

	_emotion_tag.text = (
		"   [%s]" % emotion
	)

	_set_portrait(emotion)
	_pop_portrait()

	_text.text = str(
		line.get(
			"text",
			""
		)
	)

	_text.visible_ratio = 0.0

	if _typing:
		_typing.kill()

	_typing = create_tween()

	_typing.tween_property(
		_text,
		"visible_ratio",
		1.0,
		maxf(
			0.5,
			_text.text.length() * 0.02
		)
	)

	_typing.finished.connect(
		func():
			_show_choices(
				line.get(
					"choices",
					[]
				)
			)
	)


# --------------------------------------------------
# JOHNSON'S DIALOGUE
# --------------------------------------------------

func _show_player_line(
	player_text: String
) -> void:

	_stop_thinking()

	for child in _choices.get_children():
		child.queue_free()

	_speaker.text = "Johnson Jeng"
	_emotion_tag.text = ""

	_text.text = player_text
	_text.visible_ratio = 0.0

	if _typing:
		_typing.kill()

	_typing = create_tween()

	_typing.tween_property(
		_text,
		"visible_ratio",
		1.0,
		maxf(
			0.5,
			player_text.length() * 0.02
		)
	)

	# Johnson is now speaking.
	_johnson_speaking = true
	_johnson_text_finished = false

	# Once his text finishes, check whether Gemini
	# has also finished generating the response.
	_typing.finished.connect(
		func():
			_johnson_text_finished = true
			_try_show_pending_response()
	)


# --------------------------------------------------
# CHOICES
# --------------------------------------------------

func _show_choices(
	choices: Array
) -> void:

	for child in _choices.get_children():
		child.queue_free()

	if (
		GameState.dumped[char_id]
		or exchanges >= MAX_EXCHANGES
	):
		var done := Button.new()

		if GameState.dumped[char_id]:
			done.text = "Leave"
		else:
			done.text = "End date"

		done.pressed.connect(
			_end_date
		)

		_choices.add_child(done)

		return

	for choice in choices:
		var button := Button.new()

		button.text = str(
			choice["text"]
		)

		button.pressed.connect(
			_on_choice.bind(choice)
		)

		_choices.add_child(button)


func _on_choice(
	choice: Dictionary
) -> void:

	exchanges += 1

	var player_text: String = str(
		choice["text"]
	)

	var tone: String = str(
		choice["tone"]
	)

	_last_player_text = player_text

	var delta: int = GameState.apply_tone(
		char_id,
		tone
	)

	_show_trust(
		delta,
		true
	)

	_update_debug()

	# --------------------------------------------------
	# Reset response state.
	# --------------------------------------------------

	_johnson_speaking = true
	_johnson_text_finished = false

	_response_ready = false
	_pending_response.clear()

	# --------------------------------------------------
	# Start Johnson's dialogue.
	# --------------------------------------------------

	_show_player_line(
		player_text
	)

	# --------------------------------------------------
	# At the SAME TIME, ask Gemini for the response.
	#
	# We do NOT show [thinking...] here because Johnson's
	# dialogue itself fills the API waiting time.
	# --------------------------------------------------

	GeminiClient.request_line(
		char_id,
		_beat(),
		player_text,
		tone
	)


# --------------------------------------------------
# END DATE
# --------------------------------------------------

func _end_date() -> void:
	GameState.finish_date(
		char_id
	)

	GameState.go_next()


# --------------------------------------------------
# DEBUG
# --------------------------------------------------

func _update_debug() -> void:
	_debug.text = (
		"DEBUG: spy is %s | trustmeter %+d"
		% [
			GameState.characters[
				GameState.spy_id
			]["name"],
			GameState.trustmeter
		]
	)


# --------------------------------------------------
# TRUST METER
# --------------------------------------------------

func _show_trust(
	delta: int,
	animate: bool
) -> void:

	var trust: int = (
		GameState.trust[char_id]
	)

	var color := Color.from_hsv(
		clampf(
			trust / 100.0,
			0.0,
			1.0
		) * 0.33,
		0.65,
		1.0
	)

	_trust_state.text = (
		GameState.trust_label(char_id)
	)

	_trust_state.add_theme_color_override(
		"font_color",
		color
	)

	_trust_bar.modulate = color

	if not animate:
		_trust_bar.value = trust
		return

	create_tween().tween_property(
		_trust_bar,
		"value",
		float(trust),
		0.4
	).set_trans(
		Tween.TRANS_CUBIC
	)

	if delta == 0:
		return

	_trust_delta.text = (
		"%+d" % delta
	)

	if delta > 0:
		_trust_delta.add_theme_color_override(
			"font_color",
			Color(
				0.45,
				1.0,
				0.55
			)
		)
	else:
		_trust_delta.add_theme_color_override(
			"font_color",
			Color(
				1.0,
				0.4,
				0.4
			)
		)

	_trust_delta.position.y = 40.0
	_trust_delta.modulate.a = 1.0

	var tween := (
		create_tween()
		.set_parallel(true)
	)

	tween.tween_property(
		_trust_delta,
		"position:y",
		12.0,
		1.1
	)

	tween.tween_property(
		_trust_delta,
		"modulate:a",
		0.0,
		1.1
	).set_delay(
		0.4
	)
