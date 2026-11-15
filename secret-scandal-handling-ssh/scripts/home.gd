extends Control
## Start menu: background + start button -> date picker.

func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://art/backgrounds/HomeScreen.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)

	var btn := TextureButton.new()
	btn.texture_normal = load("res://art/buttons/HomeScreenButton.png")
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(320, 100)
	btn.position = Vector2(480, 590)
	btn.size = Vector2(320, 100)
	btn.pressed.connect(func():
		GameState.new_run()
		get_tree().change_scene_to_file("res://scenes/date_select.tscn"))
	add_child(btn)

	var label := Label.new()
	label.text = "START"
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.9, 0.1, 0.5))
	label.add_theme_constant_override("outline_size", 8)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)
