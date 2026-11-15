extends Control
## Test scene: pick which of the 5 characters to take on a date. Shows the hidden spy for debugging (F1 toggles).

var _debug_label: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Choose a date  (day %d - %d dates left)" % [GameState.day, GameState.dates_left]
	title.add_theme_font_size_override("font_size", 32)
	title.position = Vector2(60, 40)
	add_child(title)

	var box := VBoxContainer.new()
	box.position = Vector2(60, 120)
	box.custom_minimum_size = Vector2(700, 0)
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	for id in GameState.characters.keys():
		var c: Dictionary = GameState.characters[id]
		var b := Button.new()
		b.text = "%s   -   %s" % [c["name"], c["location"].get_file().get_basename().replace("_", " ")]
		b.custom_minimum_size = Vector2(700, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_pick.bind(id))
		box.add_child(b)

	var again := Button.new()
	again.text = "Re-roll the spy (new run)"
	again.pressed.connect(func():
		GameState.new_run()
		_update_debug())
	box.add_child(again)

	var home := Button.new()
	home.text = "Back to start menu"
	home.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/home.tscn"))
	box.add_child(home)

	_debug_label = Label.new()
	_debug_label.position = Vector2(60, 680)
	_debug_label.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	add_child(_debug_label)
	_update_debug()


func _update_debug() -> void:
	_debug_label.text = "DEBUG (F1 hides): the spy this run is %s" % GameState.characters[GameState.spy_id]["name"]


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F1:
		_debug_label.visible = not _debug_label.visible


func _on_pick(id: String) -> void:
	GameState.set_meta("current_date", id)
	get_tree().change_scene_to_file("res://scenes/date_scene.tscn")
