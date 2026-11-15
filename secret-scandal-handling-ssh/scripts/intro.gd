extends Control

var slides = [
	{
		"texture": preload("res://art/intro-scene/Midnight Call in the City.jpeg"),
		"action_texture": preload("res://art/intro-scene/Throwing Blanket Aside & Rushing Out of Bed.jpeg"),
		"text_parts": [
			"(The President...? At this hour?)",
			"\"Figure this out, Jeng... or else.\""
		]
	},
	{
		"texture": preload("res://art/intro-scene/Unauthorized Access — Security Breach.jpeg"),
		"action_texture": null,
		"text": "“Someone used my trust against me.”"
	},
	{
		"texture": preload("res://art/intro-scene/Midnight ECLIPSE Access Investigation.jpeg"),
		"action_texture": preload("res://art/intro-scene/Slamming File & Reaching for Keyboard.jpeg"),
		"text_parts": [
			"The only people who could have accessed this...",
			"are the five women closest to me."
		]
	},
	{
		"texture": preload("res://art/intro-scene/Five Suspects, One Hidden Conspiracy.jpeg"),
		"action_texture": preload("res://art/intro-scene/Suspects Turning & Stepping Forward.jpeg"),
		"text_parts": [
			"Five suspects...",
			"One hidden conspiracy."
		]
	},
	{
		"texture": preload("res://art/intro-scene/Johnson Jeng's Project Eclipse Crisis.jpeg"),
		"action_texture": preload("res://art/intro-scene/Leaning Forward & Pointing at Laptop.jpeg"),
		"text_parts": [
			"*sigh...*",
			"I have one week to find out who it is..."
		],
		"lower_text": true
	},
	{
		"texture": preload("res://art/intro-scene/Task 1 Highlighted.jpeg"),
		"action_texture": null,
		"text": "",
		"task_sequence": [
			preload("res://art/intro-scene/Task 2 Highlighted.jpeg"),
			preload("res://art/intro-scene/Task 3 Highlighted.jpeg"),
			preload("res://art/intro-scene/Task 4 Highlighted.jpeg")
		]
	}
]


# Which main slide we are currently on.
var current: int = 0

# Dynamically created dialogue label.
var dialogue_label: Label

# Tweens used for animations.
var text_tween: Tween
var briefing_tween: Tween

# Mission briefing state.
var task_index: int = 0
var briefing_active: bool = false

# Which text part is currently being shown
# inside a multi-part slide.
var text_part_index: int = 0


func _ready() -> void:
	await _setup_ui()

	if dialogue_label == null:
		push_error("DialogueLabel failed to initialize.")
		return

	show_slide(0)


func _setup_ui() -> void:
	# Wait one frame so Control sizes are ready.
	await get_tree().process_frame

	$background.scale = Vector2.ONE

	# Remove an old dynamically-created dialogue label
	# if one somehow already exists.
	var old_label: Node = $background.get_node_or_null("DialogueLabel")

	if old_label != null:
		old_label.queue_free()
		await old_label.tree_exited

	# Create the dialogue label.
	dialogue_label = Label.new()
	dialogue_label.name = "DialogueLabel"

	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.clip_contents = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	dialogue_label.add_theme_color_override(
		"font_color",
		Color("#1e1826")
	)

	dialogue_label.add_theme_constant_override(
		"line_spacing",
		2
	)

	$background.add_child(dialogue_label)

	_update_dialogue_box_rect()

	# Reposition the dialogue whenever the background changes size.
	if not $background.resized.is_connected(_update_dialogue_box_rect):
		$background.resized.connect(_update_dialogue_box_rect)

	# Make the Next button cover the screen.
	if has_node("nextButton"):
		$nextButton.text = ""
		$nextButton.flat = true
		$nextButton.focus_mode = Control.FOCUS_NONE

		$nextButton.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND
		)

		$nextButton.position = $background.position
		$nextButton.size = $background.size

		move_child(
			$nextButton,
			get_child_count() - 1
		)


func _update_dialogue_box_rect() -> void:
	if dialogue_label == null:
		return

	# Explicit Vector2 type prevents Godot's type inference error.
	var bg_size: Vector2 = $background.size

	var adaptive_font_size: int = int(
		bg_size.y * 0.032
	)

	dialogue_label.add_theme_font_size_override(
		"font_size",
		adaptive_font_size
	)

	dialogue_label.position = Vector2(
		bg_size.x * 0.155,
		bg_size.y * 0.825
	)

	dialogue_label.size = Vector2(
		bg_size.x * 0.68,
		bg_size.y * 0.13
	)


func show_slide(index: int) -> void:
	if index < 0 or index >= slides.size():
		return

	var slide: Dictionary = slides[index]

	# Stop old animations.
	if text_tween:
		text_tween.kill()
		text_tween = null

	if briefing_tween:
		briefing_tween.kill()
		briefing_tween = null

	# Show the starting image for this slide.
	$background.texture = slide["texture"]

	briefing_active = false
	text_part_index = 0

	# Reset dialogue position.
	_update_dialogue_box_rect()

	# Certain slides move their dialogue slightly lower.
	if slide.get("lower_text", false):
		var bg_size: Vector2 = $background.size

		dialogue_label.position.y = (
			bg_size.y * 0.85
		)

	# --------------------------------------------------
	# Mission briefing
	# --------------------------------------------------

	if slide.has("task_sequence"):
		briefing_active = true
		task_index = 0

		var seq: Array = slide["task_sequence"]

		briefing_tween = (
			create_tween()
			.set_loops()
		)

		briefing_tween.tween_interval(2.5)

		briefing_tween.tween_callback(
			func():
				if task_index < seq.size():
					$background.texture = seq[task_index]
					task_index += 1

				else:
					if briefing_tween:
						briefing_tween.kill()
		)

	# --------------------------------------------------
	# Multi-part dialogue
	# --------------------------------------------------

	if slide.has("text_parts"):
		var parts: Array = slide["text_parts"]

		if parts.size() > 0:
			_start_text(
				str(parts[0])
			)

		return

	# --------------------------------------------------
	# Normal single-text slide
	# --------------------------------------------------

	_start_text(
		str(
			slide.get(
				"text",
				""
			)
		)
	)


func _start_text(new_text: String) -> void:
	if dialogue_label == null:
		push_error(
			"Cannot start text because dialogue_label is null."
		)
		return

	dialogue_label.text = new_text
	dialogue_label.visible_characters = 0

	if new_text == "":
		return

	if text_tween:
		text_tween.kill()

	text_tween = create_tween()

	var total_chars: int = new_text.length()

	var duration: float = clampf(
		total_chars * 0.03,
		1.0,
		2.5
	)

	text_tween.tween_property(
		dialogue_label,
		"visible_characters",
		total_chars,
		duration
	)


func _append_text(new_text: String) -> void:
	if dialogue_label == null:
		return

	if text_tween:
		text_tween.kill()

	var old_length: int = dialogue_label.text.length()

	# Keep the old text and place the new text underneath it.
	dialogue_label.text += "\n" + new_text

	# Keep all old text visible immediately.
	dialogue_label.visible_characters = old_length + 1

	text_tween = create_tween()

	var total_chars: int = dialogue_label.text.length()

	var duration: float = clampf(
		new_text.length() * 0.03,
		0.8,
		2.0
	)

	text_tween.tween_property(
		dialogue_label,
		"visible_characters",
		total_chars,
		duration
	)


func next() -> void:
	if dialogue_label == null:
		return

	var slide: Dictionary = slides[current]

	# --------------------------------------------------
	# Finish currently typing dialogue first
	# --------------------------------------------------

	if (
		text_tween
		and dialogue_label.visible_characters
		< dialogue_label.text.length()
	):
		text_tween.kill()
		text_tween = null

		dialogue_label.visible_characters = (
			dialogue_label.text.length()
		)

		return

	# --------------------------------------------------
	# Mission briefing
	# --------------------------------------------------

	if slide.has("task_sequence"):
		var seq: Array = slide["task_sequence"]

		# If still cycling, skip directly to Task 4.
		if (
			briefing_active
			and task_index < seq.size()
		):
			if briefing_tween:
				briefing_tween.kill()
				briefing_tween = null

			$background.texture = (
				seq[seq.size() - 1]
			)

			task_index = seq.size()

			return

		# Task 4 is already visible.
		# Move into the date selection scene.
		get_tree().change_scene_to_file(
			"res://scenes/date_select.tscn"
		)

		return

	# --------------------------------------------------
	# Multi-part dialogue
	# --------------------------------------------------

	if slide.has("text_parts"):
		var parts: Array = slide["text_parts"]

		if text_part_index < parts.size() - 1:
			text_part_index += 1

			# When Part 2 begins, switch to the
			# action image for this slide.
			if (
				text_part_index == 1
				and slide.get(
					"action_texture"
				) != null
			):
				$background.texture = (
					slide["action_texture"]
				)

			_append_text(
				str(
					parts[text_part_index]
				)
			)

			return

	# --------------------------------------------------
	# Next main slide
	# --------------------------------------------------

	if current < slides.size() - 1:
		current += 1

		show_slide(current)


func _on_next_button_pressed() -> void:
	next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		next()
