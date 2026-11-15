extends Control

## Date picker. The five outlines are Polygon2D shapes under "Girls".
## Hovering highlights one woman and clicking begins her date.

const GLOW_COLOR := Color(1.0, 0.30, 0.68)
const CORE_COLOR := Color(1.0, 0.82, 0.93)

const GLOW_LAYERS := [
	[64.0, 0.07],
	[40.0, 0.12],
	[24.0, 0.20],
	[12.0, 0.38]
]

const CORE_WIDTH := 4.0
const DIM_AMOUNT := 0.55

@onready var _girls: Node2D = %Girls
@onready var _dim: ColorRect = %Dim
@onready var _info_name: Label = %InfoName
@onready var _info_detail: Label = %InfoDetail
@onready var _debug_box: Control = %Debug
@onready var _debug_label: Label = %DebugLabel

var _ids: Array = []
var _glow: Dictionary = {}

var _hover := ""

var _pulse: Tween
var _dim_tween: Tween


func _ready() -> void:
	if GameState.dumped_count() >= GameState.characters.size():
		get_tree().change_scene_to_file.call_deferred(
			"res://scenes/ending.tscn"
		)
		return

	%Sub.text = "Day %d  -  %d dates left" % [
		GameState.day,
		GameState.dates_left
	]

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	for g in _girls.get_children():
		var id := String(g.name)

		if not GameState.characters.has(id):
			continue

		_ids.append(id)

		var poly := g as Polygon2D

		if poly == null:
			continue

		poly.uv = poly.polygon
		poly.color = Color(1.12, 1.08, 1.12)

		var holder := Node2D.new()
		holder.visible = false

		poly.add_child(holder)

		for layer in GLOW_LAYERS:
			holder.add_child(
				_make_line(
					poly.polygon,
					float(layer[0]),
					Color(
						GLOW_COLOR,
						float(layer[1])
					),
					additive
				)
			)

		holder.add_child(
			_make_line(
				poly.polygon,
				CORE_WIDTH,
				Color(CORE_COLOR, 0.95),
				additive
			)
		)

		_glow[id] = holder

	%BackButton.pressed.connect(
		func():
			get_tree().change_scene_to_file(
				"res://scenes/home.tscn"
			)
	)

	%RerollButton.pressed.connect(
		func():
			GameState.new_run()
			_update_debug()
	)

	%EndGameButton.pressed.connect(
		func():
			get_tree().change_scene_to_file(
				"res://scenes/ending.tscn"
			)
	)

	_update_debug()


func _make_line(
	points: PackedVector2Array,
	width: float,
	color: Color,
	mat: Material
) -> Line2D:

	var line := Line2D.new()

	line.points = points
	line.closed = true
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	line.material = mat

	return line


func _id_at(screen_pos: Vector2) -> String:
	var local_pos := _girls.to_local(screen_pos)

	for id in _ids:
		var poly := (
			_girls.get_node(NodePath(id))
			as Polygon2D
		)

		if poly == null:
			continue

		if Geometry2D.is_point_in_polygon(
			local_pos,
			poly.polygon
		):
			return id

	return ""


func _set_hover(id: String) -> void:
	if id == _hover:
		return

	_hover = id

	for k in _ids:
		var selected: bool = (k == id)

		var girl := _girls.get_node(
			NodePath(k)
		)

		girl.visible = selected

		if _glow.has(k):
			_glow[k].visible = selected

	if _pulse:
		_pulse.kill()
		_pulse = null

	if _dim_tween:
		_dim_tween.kill()
		_dim_tween = null

	_dim_tween = create_tween()

	_dim_tween.tween_property(
		_dim,
		"color:a",
		DIM_AMOUNT if id != "" else 0.0,
		0.15
	)

	if id == "":
		_info_name.text = "Hover over someone"
		_info_detail.text = "Click a girl to start your date"

		Input.set_default_cursor_shape(
			Input.CURSOR_ARROW
		)

		return

	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND
	)

	var character: Dictionary = (
		GameState.characters[id]
	)

	_info_name.text = character["name"]

	var place: String = (
		character["location"]
		.get_file()
		.get_basename()
	)

	place = (
		RegEx
		.create_from_string("-\\d+$")
		.sub(place, "")
		.replace("_", " ")
	)

	place = (
		place
		.trim_suffix(" Interior")
		.trim_suffix(" Workspace")
	)

	if GameState.dumped[id]:
		_info_detail.text = (
			"%s ended things with you."
			% character["name"]
		)

	elif GameState.has_dated_today(id):
		_info_detail.text = (
			"You already saw %s today."
			% character["name"]
		)

	else:
		_info_detail.text = (
			"%s   -   %s   -   Trustmeter: %s"
			% [
				character["role"],
				place,
				GameState.trust_label(id)
			]
		)

	var glow_node: Node2D = _glow[id]

	glow_node.modulate.a = 1.0

	_pulse = (
		create_tween()
		.set_loops()
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN_OUT)
	)

	_pulse.tween_property(
		glow_node,
		"modulate:a",
		0.6,
		0.7
	)

	_pulse.tween_property(
		glow_node,
		"modulate:a",
		1.0,
		0.7
	)


func _update_debug() -> void:
	_debug_label.text = (
		"DEBUG (F1 hides): spy is %s | trustmeter %+d"
		% [
			GameState.characters[
				GameState.spy_id
			]["name"],
			GameState.trustmeter
		]
	)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover(
			_id_at(event.position)
		)

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			_debug_box.visible = (
				not _debug_box.visible
			)

		elif (
			event.keycode == KEY_LEFT
			or event.keycode == KEY_RIGHT
		):
			if _ids.is_empty():
				return

			var index := _ids.find(_hover)

			index = (
				0
				if index < 0
				else posmod(
					index + (
						1
						if event.keycode == KEY_RIGHT
						else -1
					),
					_ids.size()
				)
			)

			_set_hover(
				_ids[index]
			)

		elif (
			event.keycode == KEY_ENTER
			or event.keycode == KEY_KP_ENTER
		) and _hover != "":
			_on_pick(_hover)


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and _hover != ""
	):
		_on_pick(_hover)


func _on_pick(id: String) -> void:
	if GameState.dumped[id]:
		return

	if GameState.has_dated_today(id):
		return

	Input.set_default_cursor_shape(
		Input.CURSOR_ARROW
	)

	GameState.set_meta(
		"current_date",
		id
	)

	get_tree().change_scene_to_file(
		"res://scenes/date_scene.tscn"
	)
