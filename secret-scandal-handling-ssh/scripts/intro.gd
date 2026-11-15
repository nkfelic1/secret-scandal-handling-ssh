extends Control

<<<<<<< Updated upstream
var images = [
	preload("res://.godot/imported/Midnight_Call_in_the_City-1.png-02ecc79bd96db0b85194b463320c4ae2.ctex"),
	preload("res://.godot/imported/Project_ECLIPSE__Unauthorized_Access-4.png-0566a7506376f793284785d0b29a69f0.ctex"),
	preload("res://.godot/imported/Midnight_ECLIPSE_Access_Investigation-2.png-07f077edd50e234d4a4c2b4f984eb85f.ctex"),
	preload("res://.godot/imported/Five_Suspects_One_Hidden_Conspiracy-3.png-5f533fc6f20f8fb30de538f82d7bfe19.ctex"),
	preload("res://.godot/imported/Johnson_Jengs_Project_Eclipse_Crisis-5.png-1d13f7a3004b2142f8842e43b1fe16ab.ctex"),
	preload("res://.godot/imported/Mission_Briefing__Project_Eclipse-6.png-7ca95c371e91369d45e7d06c2a5df857.ctex")
]

# current background img
var current = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func next():
	if current < images.size() - 1:
		current = current + 1
		$background.texture = images[current]
		
func _on_next_button_pressed() -> void:
	next()
	
=======
# contains all of the dialogue information.
# array of dictionaries
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
		"action_delay": 0.0,
		"text": "",
		"task_sequence": [
			preload("res://art/intro-scene/Task 2 Highlighted.jpeg"),
			preload("res://art/intro-scene/Task 3 Highlighted.jpeg"),
			preload("res://art/intro-scene/Task 4 Highlighted.jpeg")
		]
	}
]

var current: int = 0
var dialogue_label: Label
var text_tween: Tween
var action_tween: Tween
var briefing_tween: Tween
var task_index: int = 0
var briefing_active: bool = false

# Keeps track of which text part we're currently showing
# within a multi-part slide.
var text_part_index: int = 0


func _ready() -> void:
	await _setup_ui()
	show_slide(0)


func _setup_ui() -> void:
	await get_tree().process_frame
	
	$background.scale = Vector2.ONE
	
	dialogue_label = Label.new()
	dialogue_label.name = "DialogueLabel"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.clip_contents = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	dialogue_label.add_theme_color_override("font_color", Color("#1e1826"))
	dialogue_label.add_theme_constant_override("line_spacing", 2)
	
	$background.add_child(dialogue_label)
	_update_dialogue_box_rect()
	$background.resized.connect(_update_dialogue_box_rect)
	
	if has_node("nextButton"):
		$nextButton.text = ""
		$nextButton.flat = true
		$nextButton.focus_mode = Control.FOCUS_NONE
		$nextButton.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		$nextButton.position = $background.position
		$nextButton.size = $background.size
		move_child($nextButton, get_child_count() - 1)


func _update_dialogue_box_rect() -> void:
	if not dialogue_label:
		return
	
	var bg_size = $background.size
	
	var adaptive_font_size = int(bg_size.y * 0.032)
	dialogue_label.add_theme_font_size_override("font_size", adaptive_font_size)
	
	dialogue_label.position = Vector2(
		bg_size.x * 0.155,
		bg_size.y * 0.825
	)
	
	dialogue_label.size = Vector2(
		bg_size.x * 0.68,
		bg_size.y * 0.13
	)


func show_slide(index: int) -> void:
	var slide = slides[index]
	
	if text_tween:
		text_tween.kill()
	
	if action_tween:
		action_tween.kill()
	
	if briefing_tween:
		briefing_tween.kill()
	
	$background.texture = slide["texture"]
	
	briefing_active = false
	text_part_index = 0
	
	# Reset dialogue position to its normal position first.
	_update_dialogue_box_rect()
	
	# Some slides can move their dialogue slightly lower.
	if slide.get("lower_text", false):
		var bg_size = $background.size
		dialogue_label.position.y = bg_size.y * 0.85
	
	# Mission Briefing:
	# Cycles through Tasks 1 -> 2 -> 3 -> 4.
	if slide.has("task_sequence"):
		briefing_active = true
		task_index = 0
		
		var seq: Array = slide["task_sequence"]
		
		briefing_tween = create_tween().set_loops()
		
		briefing_tween.tween_interval(2.5)
		
		briefing_tween.tween_callback(func():
			if task_index < seq.size():
				$background.texture = seq[task_index]
				task_index += 1
			else:
				briefing_tween.kill()
		)
	
	# Multi-part dialogue slide.
	if slide.has("text_parts"):
		var parts: Array = slide["text_parts"]
		_start_text(parts[0])
		return
	
	# Normal single-text slide.
	_start_text(slide["text"])


func _start_text(new_text: String) -> void:
	dialogue_label.text = new_text
	dialogue_label.visible_characters = 0
	
	if new_text == "":
		return
	
	text_tween = create_tween()
	
	var total_chars = new_text.length()
	
	# Natural typing speed.
	var duration = clamp(
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
	if text_tween:
		text_tween.kill()
	
	# Remember how much text was already visible.
	var old_length = dialogue_label.text.length()
	
	# Keep the previous text and place the new dialogue
	# underneath it.
	dialogue_label.text += "\n" + new_text
	
	# Keep all of the old dialogue visible.
	dialogue_label.visible_characters = old_length + 1
	
	text_tween = create_tween()
	
	var total_chars = dialogue_label.text.length()
	
	# Only base the typing duration on the newly added text.
	var duration = clamp(
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
	var slide = slides[current]
	
	# ----------------------------------------------------
	# If text is still typing:
	# First click immediately finishes the current text.
	# ----------------------------------------------------
	
	if dialogue_label and text_tween:
		if dialogue_label.visible_characters < dialogue_label.text.length():
			text_tween.kill()
			dialogue_label.visible_characters = dialogue_label.text.length()
			return
	
	# ----------------------------------------------------
	# Mission Briefing slide
	# ----------------------------------------------------
	
	if slide.has("task_sequence"):
		
		# If the automatic Task sequence hasn't finished,
		# clicking skips immediately to Task 4.
		if briefing_active and task_index < slide["task_sequence"].size():
			
			if briefing_tween:
				briefing_tween.kill()
			
			var seq: Array = slide["task_sequence"]
			
			$background.texture = seq[seq.size() - 1]
			task_index = seq.size()
			
			return
		
		else:
			# Once Task 4 is being displayed,
			# another click enters the date selection scene.
			get_tree().change_scene_to_file(
				"res://scenes/date_select.tscn"
			)
			
			return
	
	# ----------------------------------------------------
	# Multi-part dialogue
	# ----------------------------------------------------
	
	if slide.has("text_parts"):
		var parts: Array = slide["text_parts"]
		
		# There is another piece of dialogue to display.
		if text_part_index < parts.size() - 1:
			
			text_part_index += 1
			
			# When the second part begins, switch to the
			# action image for this slide.
			if text_part_index == 1 and slide["action_texture"] != null:
				$background.texture = slide["action_texture"]
			
			# Keep the previous dialogue and type the
			# new dialogue underneath it.
			_append_text(parts[text_part_index])
			
			return
	
	# ----------------------------------------------------
	# Current slide is completely finished.
	# Move to the next actual slide.
	# ----------------------------------------------------
	
	if current < slides.size() - 1:
		current += 1
		show_slide(current)


func _on_next_button_pressed() -> void:
	next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		next()
>>>>>>> Stashed changes
