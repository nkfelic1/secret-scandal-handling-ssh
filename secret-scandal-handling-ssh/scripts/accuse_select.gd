extends Control

## End-of-day accusation (days 2-5). Same layout as the date picker: the five
## outlines are Polygon2D shapes under "Girls". Hovering highlights one woman,
## clicking opens a confirmation popup, and confirming accuses her via
## GameState.accuse().
##
## Correct: the leak is stopped and the game ends (earlier = better ending).
## Wrong: she breaks up with Johnson, the affair goes public, and she can't be
## dated or accused again. On the last day a wrong guess is the final failure.

const GLOW_COLOR := Color(1.0, 0.18, 0.22)
const CORE_COLOR := Color(1.0, 0.86, 0.82)

const GLOW_LAYERS := [
	[64.0, 0.07],
	[40.0, 0.12],
	[24.0, 0.20],
	[12.0, 0.38]
]

const CORE_WIDTH := 4.0
const DIM_AMOUNT := 0.6

## Dark wash drawn over women who were already (wrongly) accused.
const ACCUSED_SHADE := Color(0.03, 0.0, 0.02, 0.72)
const ACCUSED_LABEL_SIZE := 44

## What she says when Johnson accuses her and she is innocent. She breaks up with him.
const INNOCENT_REACTIONS := {
	"nvision_swe": "Me? Leak NVision? I... I would never. I can't believe you'd even think that. We're done, Johnson. Please don't come by my desk anymore.",
	"amd_employee": "You think I'm some DMA spy? Wow. After everything... It's not like I was hiding anything that would hurt YOU. We're finished. Go interrogate someone else.",
	"childhood_sweetheart": "Johnson... we've known each other since we were kids. And you really think I'd do that to you? I need you to leave. Please.",
	"startup_ceo": "Unbelievable. You've always doubted me, and now this. Don't call me. Don't text me. Whatever this was, it's over.",
	"shareholder": "How very bold of you, darling. And how very wrong. Consider our little arrangement over, and don't expect my vote at the next board meeting.",
}

## What she says when Johnson catches her. Her mask slips.
const GUILTY_REACTIONS := {
	"nvision_swe": "...Fine. Yes, it was me. Do you know how many weekends I've given this company? Somebody had to make you pay for it.",
	"amd_employee": "So you finally figured it out. Took you long enough. DMA sends its regards, Johnson.",
	"childhood_sweetheart": "You never once took me seriously. My company was going to be the one thing you couldn't ignore.",
	"startup_ceo": "Took you long enough. Maybe if you'd ever actually let me in, I wouldn't have wanted to burn it all down.",
	"shareholder": "Oh, darling. Did you really think I didn't know about the others? Consider it my parting gift.",
}

@onready var _girls: Node2D = %Girls
@onready var _dim: ColorRect = %Dim
@onready var _info_name: Label = %InfoName
@onready var _info_detail: Label = %InfoDetail
@onready var _debug_box: Control = %Debug
@onready var _debug_label: Label = %DebugLabel

@onready var _modal: Control = %Modal
@onready var _popup_portrait: TextureRect = %Portrait
@onready var _popup_title: Label = %PopupTitle
@onready var _popup_body: RichTextLabel = %PopupBody
@onready var _cancel_button: Button = %CancelButton
@onready var _confirm_button: Button = %ConfirmButton

var _ids: Array = []
var _glow: Dictionary = {}

var _hover := ""

## "" = picking, "confirm" = asking "are you sure?", "result" = showing what happened.
var _modal_state := ""
var _pending := ""
var _was_correct := false

var _pulse: Tween
var _dim_tween: Tween


func _ready() -> void:
	# Arrived here with nothing to do (e.g. today's accusation already made): keep the story moving.
	if not GameState.accusation_due():
		GameState.go_next.call_deferred()
		return

	if GameState.day >= GameState.LAST_DAY:
		%Sub.text = "Day %d  -  Final chance: accuse one of them" % GameState.day
	else:
		%Sub.text = "Day %d  -  Accuse one of them before the day ends" % GameState.day

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

	# Shade women who are already ruled out. Added after the outlines so it
	# always draws on top, even while she is hovered.
	for id in _ids:
		if not GameState.can_accuse(id):
			_add_accused_mark(
				_girls.get_node(NodePath(id)) as Polygon2D
			)

	_cancel_button.pressed.connect(_on_cancel)
	_confirm_button.pressed.connect(_on_confirm)

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


func _add_accused_mark(poly: Polygon2D) -> void:
	if poly == null:
		return

	var shade := Polygon2D.new()
	shade.polygon = poly.polygon
	shade.color = ACCUSED_SHADE
	_girls.add_child(shade)

	var box := Rect2(poly.polygon[0], Vector2.ZERO)
	for p in poly.polygon:
		box = box.expand(p)

	var label := Label.new()
	label.text = "ACCUSED"
	label.add_theme_font_size_override("font_size", ACCUSED_LABEL_SIZE)
	label.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(box.size.x, 60)
	label.position = Vector2(box.position.x, box.get_center().y - 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(label)


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
			# No glow on someone he can't accuse.
			_glow[k].visible = selected and GameState.can_accuse(k)

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
		_info_name.text = "Hover over a suspect"
		_info_detail.text = "Click the woman you believe is the leaker"

		Input.set_default_cursor_shape(
			Input.CURSOR_ARROW
		)

		return

	var character: Dictionary = (
		GameState.characters[id]
	)

	_info_name.text = character["name"]

	if not GameState.can_accuse(id):
		_info_detail.text = (
			"You already accused %s, and she was innocent."
			% character["name"]
		)

		Input.set_default_cursor_shape(
			Input.CURSOR_FORBIDDEN
		)

		return

	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND
	)

	var status := "Trustmeter: %s" % GameState.trust_label(id)

	if GameState.dumped[id]:
		status = "She already left you"

	_info_detail.text = (
		"%s   -   %s   -   Click to accuse"
		% [
			character["role"],
			status
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
		"DEBUG (F1 hides): spy is %s"
		% GameState.characters[
			GameState.spy_id
		]["name"]
	)


func _input(event: InputEvent) -> void:
	# While the popup is open, only its buttons (and Esc to back out) work.
	if _modal_state != "":
		if (
			event is InputEventKey
			and event.pressed
			and event.keycode == KEY_ESCAPE
			and _modal_state == "confirm"
		):
			_on_cancel()
			get_viewport().set_input_as_handled()
		return

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
			get_viewport().set_input_as_handled()
			_on_pick(_hover)


func _unhandled_input(event: InputEvent) -> void:
	if _modal_state != "":
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and _hover != ""
	):
		_on_pick(_hover)


# --------------------------------------------------
# POPUP
# --------------------------------------------------

func _on_pick(id: String) -> void:
	if not GameState.can_accuse(id):
		return

	_pending = id

	var her_name: String = GameState.characters[id]["name"]

	_set_popup_portrait(id, "surprised")

	_popup_title.text = "Accuse %s?" % her_name

	var body := (
		"You're about to accuse [b]%s[/b] of leaking NVision's secrets.\n\n"
		% her_name
	)

	body += (
		"[color=#ff7a7a][b]Warning:[/b] if %s is not the leaker, she will break up "
		+ "with you on the spot, your secret relationship with her will go public, "
		+ "and you will never be able to see her again.[/color]"
	) % her_name

	if GameState.day >= GameState.LAST_DAY:
		body += (
			"\n\n[color=#ffb070]This is your last chance. If you're wrong, "
			+ "the real leaker gets away.[/color]"
		)

	_popup_body.text = body

	_cancel_button.visible = true
	_cancel_button.text = "Not yet"
	_confirm_button.text = "Accuse %s" % her_name

	_open_modal("confirm")

	_cancel_button.grab_focus()


func _on_cancel() -> void:
	if _modal_state != "confirm":
		return

	_pending = ""
	_close_modal()


func _on_confirm() -> void:
	match _modal_state:
		"confirm":
			_resolve_accusation()
		"result":
			_continue()


func _resolve_accusation() -> void:
	var id := _pending
	var her_name: String = GameState.characters[id]["name"]

	_was_correct = GameState.accuse(id)

	var body := ""

	if _was_correct:
		_set_popup_portrait(id, "serious")
		_popup_title.text = "%s was the leaker" % her_name
		body = "\"%s\"\n\n" % GUILTY_REACTIONS.get(id, "...So you figured it out.")
		body += (
			"[color=#8fe3a0]NVision security locks down the leak before it spreads. "
			+ "The company's secrets are safe.[/color]"
		)
		_confirm_button.text = "See the headlines"

	else:
		_set_popup_portrait(id, "serious")
		_popup_title.text = "%s wasn't the leaker" % her_name
		body = "\"%s\"\n\n" % INNOCENT_REACTIONS.get(id, "How could you? We're done.")
		body += (
			"[color=#ff7a7a]%s has broken up with you, and by morning the story is everywhere: "
			+ "%s[/color]\n\n"
		) % [her_name, GameState.accusation_scandal(id)]

		if GameState.case_state == "failed":
			body += "[color=#ffb070]Out of time, the real leaker is still out there...[/color]"
			_confirm_button.text = "See the headlines"
		else:
			body += "The real leaker is still out there."
			_confirm_button.text = "End the day"

	_popup_body.text = body

	_cancel_button.visible = false

	_open_modal("result")

	_confirm_button.grab_focus()


func _continue() -> void:
	Input.set_default_cursor_shape(
		Input.CURSOR_ARROW
	)

	# Solved / final failure -> ending screen, otherwise the next day starts.
	GameState.go_next()


func _open_modal(state: String) -> void:
	_modal_state = state
	_modal.visible = true

	Input.set_default_cursor_shape(
		Input.CURSOR_ARROW
	)


func _close_modal() -> void:
	_modal_state = ""
	_modal.visible = false

	# Re-run hover so the info bar and cursor match where the mouse is now.
	var id := _hover
	_hover = "__refresh__"
	_set_hover(
		_id_at(get_viewport().get_mouse_position())
		if id == ""
		else id
	)


func _set_popup_portrait(id: String, emotion: String) -> void:
	var path := GameState.portrait_path(id, emotion)

	if ResourceLoader.exists(path):
		_popup_portrait.texture = load(path)
	else:
		_popup_portrait.texture = null
