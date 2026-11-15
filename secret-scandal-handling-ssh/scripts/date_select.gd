extends Control
## Date picker. Layout (clickable columns, panels, fonts) lives in date_select.tscn - edit it in the 2D editor.
## Each button under "Columns" is named after a character id from data/characters.json.

@onready var _columns: Control = %Columns
@onready var _info_name: Label = %InfoName
@onready var _info_detail: Label = %InfoDetail
@onready var _debug_box: Control = %Debug
@onready var _debug_label: Label = %DebugLabel


func _ready() -> void:
	%Sub.text = "Day %d  -  %d dates left" % [GameState.day, GameState.dates_left]
	for btn in _columns.get_children():
		var id := String(btn.name)
		if not GameState.characters.has(id):
			continue
		btn.pressed.connect(_on_pick.bind(id))
		btn.mouse_entered.connect(_hover.bind(id))
		btn.focus_entered.connect(_hover.bind(id))
		btn.mouse_exited.connect(_unhover)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/home.tscn"))
	%RerollButton.pressed.connect(func():
		GameState.new_run()
		_update_debug())
	_update_debug()


func _hover(id: String) -> void:
	var c: Dictionary = GameState.characters[id]
	_info_name.text = c["name"]
	_info_detail.text = "%s   -   %s" % [
		c["location"].get_file().get_basename().replace("_", " ").trim_suffix(" Interior").trim_suffix(" Workspace"),
		", ".join(c["traits"].slice(0, 2))]
	# dim everyone else so the hovered girl stands out
	for btn in _columns.get_children():
		var dim := btn.get_node_or_null("Dim")
		if dim:
			dim.visible = String(btn.name) != id


func _unhover() -> void:
	_info_name.text = "Hover over someone"
	_info_detail.text = "Click a girl to start your date"
	for btn in _columns.get_children():
		var dim := btn.get_node_or_null("Dim")
		if dim:
			dim.visible = false


func _update_debug() -> void:
	_debug_label.text = "DEBUG (F1 hides): spy is %s" % GameState.characters[GameState.spy_id]["name"]


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F1:
		_debug_box.visible = not _debug_box.visible


func _on_pick(id: String) -> void:
	GameState.set_meta("current_date", id)
	get_tree().change_scene_to_file("res://scenes/date_scene.tscn")
