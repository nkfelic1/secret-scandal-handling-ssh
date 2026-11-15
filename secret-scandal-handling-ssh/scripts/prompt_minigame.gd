extends Control
## Prompt-engineering minigame: a split-screen tablet with a "work" app (left) and Gemini (right).
## The player prompts Gemini (real API call), copies the reply into the work app, and sends it.
## Gemini then grades both the result and the prompts that produced it.
##
## Each day's task comes from data/minigame_tasks.json (via GameState.minigame_task()).
## The task's "kind" picks the left-hand app:
##   email -> the Gmail art,  post -> Nstagram post editor,  text -> Messages,  code -> NVision DevHub editor.
## Layout lives in prompt_minigame.tscn; overlays are placed in the tablet image's own pixel space.

## Score needed to earn the reward (out of 100).
const REWARD_SCORE := 75
## How much each part counts toward the 100-point total (must add up to 10).
## The finished work counts more than the prompt, which makes high scores easier.
const WORK_WEIGHT := 6.0
const PROMPT_WEIGHT := 4.0

## Johnson's expressions for the lead-in ("pose" in minigame_tasks.json).
const JOHNSON_DIR := "res://art/characters/johnson_jeng/"
const POSES := {
	"smile": "02_expression_smile", "laugh": "03_expression_laugh", "thinking": "04_expression_thinking",
	"surprised": "05_expression_surprised", "blushing": "06_expression_blushing", "serious": "07_expression_serious",
}

const CHAT_SYSTEM := """You are a helpful AI assistant inside a chat app.
Do exactly what the user asks, no more. Keep every reply under 150 words.
Use plain text only: no markdown, no asterisks, no headings.
If asked for code, reply with only the code (under 40 lines), no markdown fences."""

const GRADER_SYSTEM := """You grade a casual prompt-engineering minigame for beginners. The player had to get an AI chatbot to write a %s for a specific task, then send it.
Be GENEROUS and encouraging. Most reasonable attempts should score high.
WORK score (0-10): %s
PROMPTS score (0-10): give 7 if they at least said what it is for and who it is for. Give 9-10 if they also added any one extra detail (tone, length, key points, constraints, or a sign-off). Below 5 only for a bare request like "write a %s" with no context, or no prompt at all.
Feedback: 1-2 short, friendly sentences about the %s. Tip: one concrete way to improve their prompt next time."""

## Everything that changes with the task's "kind".
const KINDS := {
	"email": {
		"noun": "email", "sending": "Sending...", "done": "Email sent!",
		"goal": "", "instructions": "",   # the sprites already say "email"
		"tab": "", "url": "", "color": Color(0.85, 0.2, 0.2),
		"criteria": "if the email is on-task for that recipient with a sensible tone, give 9-10. Minor issues like a leftover placeholder such as [Your Name] still get 8. Give 5-7 only if the tone is clearly wrong for the recipient. Below 5 only if it is off-task, nonsense, or nearly empty.",
	},
	"post": {
		"noun": "post", "sending": "Posting...", "done": "Posted!",
		"goal": "Goal:\nPost something that calms the internet down!",
		"instructions": "Write a helpful prompt in the Gemini tab, then copy and paste the reply into the post!",
		"tab": "Nstagram", "url": "nstagram.com/create", "color": Color(0.42, 0.3, 0.96),
		"criteria": "if the post is on-message for a public audience, calm and professional, give 9-10. Being a bit long for social media or having a leftover placeholder still gets 8. Give 5-7 only if it would clearly make things worse (defensive, reveals secrets, blames people). Below 5 only if it is off-task, nonsense, or nearly empty.",
	},
	"text": {
		"noun": "text", "sending": "Sending...", "done": "Delivered!",
		"goal": "Goal:\nSend a text that smooths things over!",
		"instructions": "Write a helpful prompt in the Gemini tab, then copy and paste the reply into the text message!",
		"tab": "Messages", "url": "messages.app/chat", "color": Color(0.1, 0.45, 0.95),
		"criteria": "if the text is warm, personal and sounds like a real text message to her, give 9-10. Being a bit long or formal still gets 8. Give 5-7 only if it is cold, rude, or obviously copy-pasted (e.g. Dear Sir/Madam, [Her Name]). Below 5 only if it is off-task, nonsense, or nearly empty.",
	},
	"code": {
		"noun": "code", "sending": "Committing...", "done": "Committed!",
		"goal": "Goal:\nCommit working code using a better prompt!",
		"instructions": "Write a helpful prompt in the Gemini tab, then copy and paste the code into the editor!",
		"tab": "NVision DevHub", "url": "dev.nvision.com/editor", "color": Color(0.16, 0.6, 0.3),
		"criteria": "if the code plausibly solves the task, give 9-10, even if style is imperfect. Small bugs or a slightly different function name still get 7-8. Give 5-6 if it only partly solves it. Below 5 only if it is the wrong program, not code, or nearly empty.",
	},
}

var _task: Dictionary = {}
var _kind: Dictionary = {}
var _body: TextEdit             # the left-app field the player pastes into
var _running := false
var _busy := false
var _history: Array = []        # Gemini contents for the chat (multi-turn, so "make it shorter" works)
var _prompts: Array = []        # everything the player typed, for grading
var _log: Array = []            # [{who, text}] shown in the chat pane
var _last_reply := ""
var _recipient_ids: Array = []  # text task: character ids in the To: dropdown
var _brief_lines: Array = []    # Johnson's lead-in lines
var _brief_index := 0
var _brief_typing: Tween
var _brief_done := false
var _day_card_open := false


func _ready() -> void:
	_task = GameState.minigame_task()
	if _task.is_empty():
		_task = GameState.minigame_task(1)   # e.g. running the scene directly on a day with no task
	_kind = KINDS.get(_task.get("kind", "email"), KINDS["email"])
	_setup_left_app()

	%TaskText.text = _task.get("task", "")
	%Greeting.text = "[center]%s[/center]" % _gradient_text("Hello, " + GameState.player_name)
	if _kind["goal"] != "":
		%GoalText.text = _kind["goal"]
		%GoalText.visible = true
	if _kind["instructions"] != "":
		%InstrText.text = _kind["instructions"]
		%InstrText.visible = true
	_set_inputs_enabled(false)

	%StartButton.pressed.connect(_start)
	%AskButton.pressed.connect(_ask)
	%CopyButton.pressed.connect(_copy_reply)
	for b in [%SendButton, %PostButton, %SendTextButton, %CommitButton]:
		b.pressed.connect(_send)
	%TrashButton.pressed.connect(func(): %EmailBody.text = "")
	%PromptInput.gui_input.connect(_on_prompt_input)
	%RetryButton.pressed.connect(func():
		GameState.set_meta("minigame_retry_day", GameState.day)   # skip Johnson's lead-in on retry
		get_tree().reload_current_scene())
	%ContinueButton.text = "Start your dates" if _task.get("timing", "") == "before_dates" else "End the day"
	%ContinueButton.pressed.connect(func():
		GameState.minigame_done_today = true
		GameState.go_next())
	# Debug: skip straight past the minigame (only shown in debug builds, i.e. when run from the editor)
	%DebugSkip.visible = OS.is_debug_build()
	# Always lands on date select: if skipping ends the day (day 1), the next day's
	# opening minigame is skipped too, instead of reopening this same screen.
	%DebugSkip.pressed.connect(func():
		_running = false
		GameState.minigame_done_today = true
		if GameState.day_finished():
			GameState.end_day()
			GameState.minigame_done_today = true
		get_tree().change_scene_to_file(GameState.DATE_SELECT_SCENE))
	_begin_briefing()


# --- Lead-in: Johnson says why he's working, then picks up the tablet ---------

func _begin_briefing() -> void:
	var retry: bool = GameState.get_meta("minigame_retry_day", -1) == GameState.day
	_brief_lines = [] if retry else _task.get("intro", [])
	# "DAY N" card at HQ when this minigame opens the day (days 2-5); skipped on retry
	var show_card: bool = not retry and _task.get("timing", "") == "before_dates"
	if _brief_lines.is_empty() and not show_card:
		%Briefing.visible = false   # no lead-in for this task: straight to the instructions
		return
	%Intro.visible = false
	%BriefText.text = ""
	if _brief_lines.is_empty():
		%Briefing.visible = false
	var pose_path: String = JOHNSON_DIR + POSES.get(_task.get("pose", "thinking"), POSES["thinking"]) + ".png"
	if ResourceLoader.exists(pose_path):
		%BriefPortrait.texture = load(pose_path)
	if _task.get("night", false):
		%BriefBg.modulate = Color(0.45, 0.45, 0.7)   # after the dates: late at night
	%Briefing.gui_input.connect(func(e: InputEvent):
		if _is_click(e):
			_advance_briefing())
	if show_card:
		_open_day_card()
	else:
		_start_brief_lines()


func _is_click(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


func _open_day_card() -> void:
	_day_card_open = true
	%DayCard.visible = true
	%DayTitle.text = "DAY %d" % GameState.day
	%DayHeadline.text = _task.get("headline", "")
	%DayCard.gui_input.connect(func(e: InputEvent):
		if _is_click(e):
			_close_day_card())
	%DayImage.scale = Vector2(1.08, 1.08)   # slow push-out on the HQ shot
	create_tween().tween_property(%DayImage, "scale", Vector2.ONE, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	%DayTitle.modulate.a = 0.0
	%DayHeadline.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(%DayTitle, "modulate:a", 1.0, 0.5).set_delay(0.2)
	t.tween_property(%DayHeadline, "modulate:a", 1.0, 0.5)


func _close_day_card() -> void:
	if not _day_card_open:
		return
	_day_card_open = false
	var t := create_tween()
	t.tween_property(%DayCard, "modulate:a", 0.0, 0.45)
	await t.finished
	%DayCard.visible = false
	_start_brief_lines()


func _start_brief_lines() -> void:
	if _brief_lines.is_empty():
		_end_briefing()
		return
	# Johnson pops in from the side over the HQ background
	var home_x: float = %BriefPortrait.position.x
	%BriefPortrait.position.x = home_x + 80.0
	%BriefPortrait.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(%BriefPortrait, "position:x", home_x, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(%BriefPortrait, "modulate:a", 1.0, 0.3)
	_show_brief_line(0)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
		return
	if _day_card_open:
		get_viewport().set_input_as_handled()
		_close_day_card()
	elif %Briefing.visible and not _brief_done:
		get_viewport().set_input_as_handled()
		_advance_briefing()


func _show_brief_line(i: int) -> void:
	_brief_index = i
	var line: String = _brief_lines[i]
	%BriefText.text = line
	%BriefText.visible_ratio = 0.0
	%BriefHint.text = "Click to continue" if i < _brief_lines.size() - 1 else "Click to pick up the tablet"
	if _brief_typing:
		_brief_typing.kill()
	_brief_typing = create_tween()
	_brief_typing.tween_property(%BriefText, "visible_ratio", 1.0, maxf(0.4, line.length() * 0.025))


func _advance_briefing() -> void:
	if _brief_done:
		return
	if _brief_typing and _brief_typing.is_running():   # first click finishes the typing
		_brief_typing.kill()
		%BriefText.visible_ratio = 1.0
	elif _brief_index + 1 < _brief_lines.size():
		_show_brief_line(_brief_index + 1)
	else:
		_end_briefing()


## Fade Johnson out, slide the tablet up and the top bar down, then show the instructions popup.
func _end_briefing() -> void:
	_brief_done = true
	var tablet: Control = $Tablet
	var top_bar: Control = $TopBar
	var tablet_y := tablet.position.y
	tablet.position.y = size.y
	top_bar.position.y = -top_bar.size.y
	var t := create_tween().set_parallel()
	t.tween_property(%Briefing, "modulate:a", 0.0, 0.35)
	t.tween_property(tablet, "position:y", tablet_y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	t.tween_property(top_bar, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.35)
	await t.finished
	%Briefing.visible = false
	%Intro.modulate.a = 0.0
	%Intro.visible = true
	create_tween().tween_property(%Intro, "modulate:a", 1.0, 0.25)


## Shows the right app on the left half of the tablet and fills in its per-task details.
func _setup_left_app() -> void:
	var kind: String = _task.get("kind", "email")
	var intro_head := ""
	match kind:
		"post":
			_body = %PostBody
			%PostPane.visible = true
			%PostAccount.text = _task.get("account", "NVision")
			%PostHandle.text = _task.get("handle", "@NVision")
			%PostAvatarLetter.text = String(_task.get("account", "N")).left(1)
			%PostBody.text_changed.connect(_update_post_count)
			intro_head = "Posting as %s" % _task.get("handle", "@NVision")
		"text":
			_body = %TextBody
			%TextPane.visible = true
			%IncomingBubble.text = _task.get("incoming", "Hey... we need to talk.")
			for id in GameState.characters:
				_recipient_ids.append(id)
				%TextRecipient.add_item(GameState.characters[id]["name"])
			intro_head = "Text one of the women you're seeing"
		"code":
			_body = %CodeBody
			%CodePane.visible = true
			%CodeFile.text = _task.get("filename", "main.py")
			_setup_code_highlighting()
			intro_head = "Editing %s" % _task.get("filename", "main.py")
		_:
			_body = %EmailBody
			%ToField.text = _task.get("to", "")   # pre-filled: typing an address isn't part of the prompting skill
			%SubjectField.text = _task.get("subject", "")
			intro_head = "To: %s" % _task.get("to", "")
	if kind != "email":
		%LeftTab.visible = true
		%LeftUrl.visible = true
		%LeftTabLabel.text = _kind["tab"]
		%LeftUrlLabel.text = _kind["url"]
		var icon_style := StyleBoxFlat.new()
		icon_style.bg_color = _kind["color"]
		icon_style.set_corner_radius_all(7)
		%LeftTabIcon.add_theme_stylebox_override("panel", icon_style)
	%IntroTask.text = "%s\n\n%s" % [intro_head, _task.get("task", "")]


func _setup_code_highlighting() -> void:
	var h := CodeHighlighter.new()
	h.number_color = Color("#b5cea8")
	h.symbol_color = Color("#d4d4d4")
	h.function_color = Color("#dcdcaa")
	h.member_variable_color = Color("#9cdcfe")
	for kw in ["def", "return", "for", "in", "if", "elif", "else", "while", "and", "or", "not", "import",
			"from", "class", "True", "False", "None", "lambda", "with", "as", "try", "except", "pass", "break", "continue"]:
		h.add_keyword_color(kw, Color("#c586c0"))
	h.add_color_region("#", "", Color("#6a9955"), true)
	h.add_color_region("\"", "\"", Color("#ce9178"))
	h.add_color_region("'", "'", Color("#ce9178"))
	%CodeBody.syntax_highlighter = h


func _update_post_count() -> void:
	var n: int = %PostBody.text.length()
	%PostCount.text = "%d / 280" % n
	%PostCount.add_theme_color_override("font_color", Color(0.85, 0.2, 0.25) if n > 280 else Color(0.45, 0.46, 0.52))


## Gemini-style blue -> purple -> pink greeting, one color per letter.
func _gradient_text(text: String) -> String:
	var g := Gradient.new()
	g.set_color(0, Color("#4285f4"))
	g.set_color(1, Color("#d96570"))
	g.add_point(0.5, Color("#9b72cb"))
	var out := ""
	for i in text.length():
		out += "[color=#%s]%s[/color]" % [g.sample(float(i) / maxf(1.0, text.length() - 1)).to_html(false), text[i]]
	return out


func _start() -> void:
	%Intro.visible = false
	_running = true
	_set_inputs_enabled(true)
	%PromptInput.grab_focus()


func _set_inputs_enabled(on: bool) -> void:
	for n in [%ToField, %SubjectField, %EmailBody, %PostBody, %TextBody, %CodeBody, %PromptInput]:
		n.editable = on
	for n in [%SendButton, %TrashButton, %AskButton, %PostButton, %SendTextButton, %CommitButton, %TextRecipient]:
		n.disabled = not on


# --- Gemini chat pane ---------------------------------------------------------

## Enter sends the prompt, Shift+Enter makes a new line.
func _on_prompt_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo \
			and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and not e.shift_pressed:
		%PromptInput.accept_event()
		_ask()


func _ask() -> void:
	var prompt: String = %PromptInput.text.strip_edges()
	if prompt == "" or _busy or not _running:
		return
	_busy = true
	%AskButton.disabled = true
	%PromptInput.text = ""
	_prompts.append(prompt)
	_history.append({"role": "user", "parts": [{"text": prompt}]})
	_log.append({"who": "You", "text": prompt})
	%ChatPanel.visible = true
	%Welcome.visible = false
	_render_log(true)

	var res: Dictionary = await GeminiClient.generate(CHAT_SYSTEM, _history, {
		"thinkingConfig": {"thinkingLevel": "minimal"},
		"maxOutputTokens": 600,
	})
	_busy = false
	if not is_inside_tree():
		return
	var reply := ""
	if res["ok"]:
		reply = _strip_fences(res["text"])
		_history.append({"role": "model", "parts": [{"text": reply}]})
		_last_reply = reply
		%CopyButton.disabled = false
	else:
		_history.pop_back()   # keep user/model turns alternating
		reply = "(Gemini is unavailable right now: %s. You can still write it yourself.)" % res["error"]
	_log.append({"who": "Gemini", "text": reply})
	_render_log(false)
	%AskButton.disabled = not _running


## Drops ``` markdown fence lines so pasted code is clean.
func _strip_fences(text: String) -> String:
	var keep := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("```"):
			keep.append(line)
	return "\n".join(keep).strip_edges()


func _render_log(thinking: bool) -> void:
	var out := ""
	for entry in _log:
		var color := "#3c4043" if entry["who"] == "You" else "#1a73e8"
		out += "[color=%s][b]%s[/b][/color]\n%s\n\n" % [color, entry["who"], entry["text"].replace("[", "[lb]")]
	if thinking:
		out += "[color=#888899][i]Gemini is thinking...[/i][/color]"
	%ChatLog.text = out


func _copy_reply() -> void:
	if _last_reply == "":
		return
	DisplayServer.clipboard_set(_last_reply)
	%CopyButton.text = "Copied!"
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree():
		%CopyButton.text = "Copy reply"


# --- Sending + grading --------------------------------------------------------

func _send() -> void:
	if not _running:
		return
	var work: String = _body.text.strip_edges()
	var noun: String = _kind["noun"]
	if work == "":
		_toast("Write or paste something first!", 1.5)
		return
	_running = false
	_set_inputs_enabled(false)
	%CopyButton.disabled = true

	# "being sent" beat: fade the draft out, then grade
	_toast(_kind["sending"], 0.0)
	var t := create_tween()
	t.tween_property(_body, "modulate:a", 0.0, 0.5)
	await t.finished
	_toast(_kind["done"], 0.8)
	%Results.visible = true
	%ResultTitle.text = "Grading your %s..." % noun
	%ScoreLabel.text = ""
	%Feedback.text = ""
	var grade: Dictionary = await _grade(work)
	if not is_inside_tree():
		return
	var total := int(round(grade["work_score"] * WORK_WEIGHT + grade["prompt_score"] * PROMPT_WEIGHT))
	var title: String = ("Great %s!" % noun) if total >= REWARD_SCORE else (_kind["done"] if total >= 50 else "Yikes... it's already out there.")
	_finish(title, "Score: %d / 100   (%s %d/10, prompts %d/10)" % [total, noun, grade["work_score"], grade["prompt_score"]],
		"%s\n\n[color=#ff8fd6][b]Prompt tip:[/b][/color] %s" % [grade["feedback"], grade["tip"]], total)


func _grade(work: String) -> Dictionary:
	var prompts_text := "(none - they wrote it without the AI)"
	if not _prompts.is_empty():
		prompts_text = "\n".join(PackedStringArray(_prompts.map(func(p): return "- " + p)))
	var noun: String = _kind["noun"]
	var system := GRADER_SYSTEM % [noun, _kind["criteria"], noun, noun]
	var user := "TASK: %s\n%s\nPLAYER'S PROMPTS TO THE AI:\n%s\n\nTHE %s THEY SENT:\n%s" % [
		_task.get("task", ""), _context_for_grader(), prompts_text, noun.to_upper(), work]
	var res: Dictionary = await GeminiClient.generate(system, [{"role": "user", "parts": [{"text": user}]}], {
		"thinkingConfig": {"thinkingLevel": "minimal"},
		"maxOutputTokens": 300,
		"responseMimeType": "application/json",
		"responseSchema": {
			"type": "OBJECT",
			"properties": {
				"work_score": {"type": "INTEGER"},
				"prompt_score": {"type": "INTEGER"},
				"feedback": {"type": "STRING"},
				"tip": {"type": "STRING"},
			},
			"required": ["work_score", "prompt_score", "feedback", "tip"],
		},
	})
	var g = JSON.parse_string(res["text"]) if res["ok"] else null
	if g is Dictionary and g.has("work_score"):
		return {"work_score": clampi(int(g["work_score"]), 0, 10), "prompt_score": clampi(int(g.get("prompt_score", 0)), 0, 10),
			"feedback": str(g.get("feedback", "")).replace("[", "[lb]"), "tip": str(g.get("tip", "")).replace("[", "[lb]")}
	return _offline_grade(work)


## Extra details the grader needs for each kind of task.
func _context_for_grader() -> String:
	match _task.get("kind", "email"):
		"post":
			return "POSTED FROM: %s (%s)\n" % [_task.get("account", ""), _task.get("handle", "")]
		"text":
			var id: String = _recipient_ids[%TextRecipient.selected] if %TextRecipient.selected >= 0 else ""
			var c: Dictionary = GameState.characters.get(id, {})
			return "TEXTING: %s (%s). Her last message: \"%s\"\n" % [
				c.get("name", "her"), ", ".join(c.get("traits", [])), _task.get("incoming", "")]
		"code":
			return "FILE: %s\n" % _task.get("filename", "")
		_:
			return "TO: %s\nSUBJECT: %s\n" % [%ToField.text, %SubjectField.text]


## Rough fallback when Gemini is unreachable, so the round still ends with a score.
func _offline_grade(work: String) -> Dictionary:
	var words := work.split(" ", false).size()
	var work_score := 9 if words >= 8 else 6
	if "[" in work and _task.get("kind", "") != "code":
		work_score -= 2   # leftover [Name]-style placeholders
	var longest := 0
	for p in _prompts:
		longest = maxi(longest, p.split(" ", false).size())
	var prompt_score := clampi(4 + longest / 3, 5, 10) if not _prompts.is_empty() else 3
	return {"work_score": work_score, "prompt_score": prompt_score,
		"feedback": "(Offline grading - the AI grader couldn't be reached.)",
		"tip": "Tell the AI who it's for, what tone to use, and how long it should be."}


func _finish(title: String, score: String, feedback: String, total: int) -> void:
	var rewarded := total >= REWARD_SCORE
	GameState.set_meta("last_prompt_minigame_score", total)
	GameState.set_meta("prompt_minigame_reward", rewarded)   # hook the actual reward to this
	var reward_line := "[center][color=#ffd36b][b]Reward earned![/b][/color][/center]\n" if rewarded \
		else "[center][color=#bbbbcc]Score %d+ to earn a reward.[/color][/center]\n" % REWARD_SCORE
	%Results.visible = true
	%ResultTitle.text = title
	%ScoreLabel.text = score
	%Feedback.text = reward_line + feedback
	%Buttons.visible = true


func _toast(text: String, hide_after: float) -> void:
	%Toast.text = text
	%Toast.visible = true
	if hide_after > 0.0:
		await get_tree().create_timer(hide_after).timeout
		if is_inside_tree() and %Toast.text == text:
			%Toast.visible = false
