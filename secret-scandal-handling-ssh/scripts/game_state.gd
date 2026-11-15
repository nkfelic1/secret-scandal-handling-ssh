extends Node
## Autoload "GameState": holds the run's hidden truth. The spy is chosen HERE in code, never by the AI.

const CHARACTERS_PATH := "res://data/characters.json"
const MINIGAME_TASKS_PATH := "res://data/minigame_tasks.json"
const DATE_SELECT_SCENE := "res://scenes/date_select.tscn"
const MINIGAME_SCENE := "res://scenes/prompt_minigame.tscn"
const ENDING_SCENE := "res://scenes/ending.tscn"
const ACCUSE_SCENE := "res://scenes/accuse_select.tscn"
const LAST_DAY := 5
const FIRST_ACCUSATION_DAY := 2     # no accusation on day 1; from day 2 on, every day ends with one

var emotions: Array = []
var characters: Dictionary = {}
var spy_id: String = ""
var day: int = 1
var dates_left: int = 5
var dated_today: Array = []         # character ids already dated today
var minigame_tasks: Dictionary = {} # "day number" -> task dict, from data/minigame_tasks.json
var minigame_done_today := false
var clues_seen: Array = []          # [{character, text}]
var memory: Dictionary = {}         # character_id -> short running summary (unused for now)
var facts: Dictionary = {}          # character_id -> short facts established in conversation (kept forever)
var history: Dictionary = {}        # character_id -> [{role: "user"/"model", text}] chat turns sent to Gemini
var player_name: String = "Johnson"
var affection: Dictionary = {}      # character_id -> int (unused; see trust)

# ---- Trustmeter. Only small numbers are stored, never the actual words that were said. ----
const START_TRUST := 50
## How a reply's hidden tone changes the character's trust in Johnson.
const TONE_TRUST := {"warm": 5, "neutral": 2, "probing": -1, "rude": -6, "cruel": -12}
var trust: Dictionary = {}          # character_id -> 0..100
var dumped: Dictionary = {}         # character_id -> true once trust hits 0 (she has left him for good)
var rude_streak: Dictionary = {}    # character_id -> how many rude/cruel replies in a row to her
var trustmeter: int = 0             # overall signed score: kind replies add, mean replies subtract. Revealed at the end.
var tone_counts: Dictionary = {}    # tone -> times picked

# ---- Accusations. From day 2 on, every day ends with Johnson accusing one woman of being the leaker. ----
## What goes public when Johnson wrongly accuses each woman. She is still innocent of the leaks.
const ACCUSATION_SCANDALS := {
	"nvision_swe": "NVision CEO's secret romance with one of his own engineers raises workplace-ethics questions.",
	"amd_employee": "NVision CEO secretly involved with a woman tied to rival DMA, sparking corporate-security concerns.",
	"childhood_sweetheart": "NVision CEO's years-long secret relationship with his childhood friend comes to light.",
	"startup_ceo": "NVision CEO's hidden relationship with a rival startup founder raises conflict-of-interest concerns.",
	"shareholder": "NVision CEO secretly dating a member of his own Board, prompting a governance and board-independence crisis.",
}

var accused: Dictionary = {}        # character_id -> day she was WRONGLY accused. She has broken up with him for good.
var wrong_accusations: Array = []   # [{id, day}] in the order they happened (for news/ending screens)
var accused_today := false          # has today's accusation already been made?
var case_state := "open"            # open | solved (caught the leaker) | failed (final day ended without catching her)
var solved_day := 0                 # the day the leaker was caught (earlier = better ending), 0 if never


func _ready() -> void:
	_load_characters()
	_load_minigame_tasks()
	new_run()


func _load_characters() -> void:
	var f := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	emotions = data["emotions"]
	characters = data["characters"]


func _load_minigame_tasks() -> void:
	var f := FileAccess.open(MINIGAME_TASKS_PATH, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			minigame_tasks = data.get("days", {})


func new_run() -> void:
	randomize()
	var ids := characters.keys()
	spy_id = ids[randi() % ids.size()]
	day = 1
	dated_today.clear()
	minigame_done_today = false
	clues_seen.clear()
	for id in ids:
		memory[id] = ""
		history[id] = []
		facts[id] = []
		affection[id] = 0
		trust[id] = START_TRUST
		dumped[id] = false
		rude_streak[id] = 0
	accused.clear()
	wrong_accusations.clear()
	accused_today = false
	case_state = "open"
	solved_day = 0
	trustmeter = 0
	tone_counts = {"warm": 0, "neutral": 0, "probing": 0, "rude": 0, "cruel": 0}
	_recount_dates()


# ---- Day loop: each day = date every woman who hasn't left him + one work minigame. ----
# The minigame runs before or after the dates depending on data/minigame_tasks.json ("timing").
# Call go_next() whenever a date or minigame ends; it decides where the story goes.

func _recount_dates() -> void:
	dates_left = 0
	for id in characters:
		if not dated_today.has(id) and can_date(id):
			dates_left += 1


func finish_date(id: String) -> void:
	if not dated_today.has(id):
		dated_today.append(id)
	_recount_dates()


func has_dated_today(id: String) -> bool:
	return dated_today.has(id)


## She can still go on dates: she hasn't dumped him and he hasn't wrongly accused her.
func can_date(id: String) -> bool:
	return not dumped.get(id, false) and not is_accused(id)


## True once Johnson has wrongly accused her of being the leaker. She won't go on dates with him again.
func is_accused(id: String) -> bool:
	return accused.has(id)


func day_finished() -> bool:
	_recount_dates()
	return dates_left <= 0


func end_day() -> void:
	day += 1
	dated_today.clear()
	minigame_done_today = false
	accused_today = false
	_recount_dates()


## Today's minigame task, or {} if this day has none.
func minigame_task(for_day: int = day) -> Dictionary:
	return minigame_tasks.get(str(for_day), {})


func go_next() -> void:
	var timing: String = minigame_task().get("timing", "")
	if not minigame_done_today and (timing == "before_dates" or (timing == "after_dates" and day_finished())):
		get_tree().change_scene_to_file(MINIGAME_SCENE)
	elif day_finished():
		if accusation_due():
			get_tree().change_scene_to_file(ACCUSE_SCENE)
		elif case_state != "open" or day >= LAST_DAY:
			get_tree().change_scene_to_file(ENDING_SCENE)
		else:
			end_day()
			go_next()
	else:
		get_tree().change_scene_to_file(DATE_SELECT_SCENE)


func is_spy(id: String) -> bool:
	return id == spy_id


func active_secret(id: String) -> String:
	var c: Dictionary = characters[id]
	return c["malicious_secret"] if is_spy(id) else c["innocent_secret"]


## The day's dates (and work) are done and Johnson still has to name today's suspect.
func accusation_due() -> bool:
	return case_state == "open" and day >= FIRST_ACCUSATION_DAY and not accused_today


## Women Johnson can still accuse. Anyone he has already wrongly accused is ruled out.
## (A woman who dumped him can still be accused: she might be the leaker.)
func can_accuse(id: String) -> bool:
	return characters.has(id) and not is_accused(id)


## Johnson accuses her of being the leaker. Returns true if he caught the real leaker.
## A wrong accusation ends that relationship for good and makes it public.
func accuse(id: String) -> bool:
	accused_today = true
	if is_spy(id):
		case_state = "solved"
		solved_day = day
		return true
	accused[id] = day
	wrong_accusations.append({"id": id, "day": day})
	if day >= LAST_DAY:
		case_state = "failed"
	_recount_dates()
	return false


func accusation_scandal(id: String) -> String:
	return ACCUSATION_SCANDALS.get(id, "NVision CEO's secret relationship goes public.")


func portrait_path(id: String, emotion: String) -> String:
	var c: Dictionary = characters[id]
	var p: Dictionary = c["portraits"]
	var file: String = p.get(emotion, p.get("neutral", ""))
	return c["portrait_dir"] + file


func background_path(id: String) -> String:
	return characters[id]["location"]


## Applies the hidden tone of the reply Johnson just chose. Returns how much her trust changed.
func apply_tone(id: String, tone: String) -> int:
	if not TONE_TRUST.has(tone):
		tone = "neutral"
	var delta: int = TONE_TRUST[tone]
	trustmeter += delta
	if tone == "rude" or tone == "cruel":
		rude_streak[id] += 1
		if rude_streak[id] >= 2:
			delta -= 2 * mini(rude_streak[id] - 1, 3)
	else:
		rude_streak[id] = 0
	tone_counts[tone] += 1
	var before: int = trust[id]
	trust[id] = clampi(before + delta, 0, 100)
	if trust[id] <= 0:
		dumped[id] = true
	return trust[id] - before


func trust_label(id: String) -> String:
	var t: int = trust[id]
	if dumped[id] or t <= 0:
		return "Gone"
	if t >= 80:
		return "Adores you"
	if t >= 60:
		return "Warm"
	if t >= 40:
		return "Friendly"
	if t >= 20:
		return "Hurt"
	return "Fading"


## Plain-language guidance for the AI about how she should currently feel about Johnson.
func trust_guidance(id: String) -> String:
	var t: int = trust[id]
	if t >= 70:
		return "You adore and trust him. Be warmer and more open than usual."
	if t >= 40:
		return "You feel normally about him."
	if t >= 20:
		return "He has hurt you. Be noticeably cooler and shorter, and subtly let it show that he has been unkind."
	return "You are close to giving up on him. Be cold and distant, and you may say you are tired of how he treats you."


## The lower her trust, the more bothered she is, and the more her guard slips. Used to strengthen clues.
func bothered_bonus(id: String) -> int:
	var t: int = trust[id]
	if t < 20:
		return 2
	if t < 40:
		return 1
	return 0


func dumped_count() -> int:
	var n := 0
	for id in dumped:
		if dumped[id]:
			n += 1
	return n


## Everything the ending screen needs: the trustmeter score, a rating, and any punishment.
func ending_report() -> Dictionary:
	var rating := "Gentleman"
	if trustmeter < -40:
		rating = "Cruel"
	elif trustmeter < -15:
		rating = "Cold"
	elif trustmeter < 0:
		rating = "Careless"
	elif trustmeter < 20:
		rating = "Decent"
	var gone := dumped_count()
	var outcome := "clean"
	var punishment := ""
	if gone >= characters.size():
		outcome = "alone"
		punishment = "Every one of them has walked out of your life. When the President's call finally comes, there is no one left to confide in and no one to vouch for you. You sit alone in your office, phone silent. This is what you built, Johnson."
	elif gone >= 3 or trustmeter <= -40:
		outcome = "scandal"
		punishment = "The women you hurt compare notes. By morning your name is on every tech blog: \"Invision CEO's cruel double life.\" The board calls an emergency meeting, and no one defends you."
	elif trustmeter <= -15 or gone >= 1:
		outcome = "reputation"
		punishment = "Whispers start in the Invision hallways. Nobody says it to your face, but people stop returning your calls as quickly. Trust is slower to win back than it was to lose."
	return {"trustmeter": trustmeter, "rating": rating, "outcome": outcome, "punishment": punishment,
		"dumped": gone, "tone_counts": tone_counts.duplicate(),
		"case_state": case_state, "solved_day": solved_day, "case_summary": case_summary(),
		"wrong_accusations": wrong_accusations.duplicate(true)}


## One paragraph on how the leak investigation ended, for the ending screen.
func case_summary() -> String:
	var spy_name: String = characters[spy_id]["name"]
	var text := ""
	if case_state == "solved":
		if solved_day <= FIRST_ACCUSATION_DAY:
			text = "You named %s as the leaker on day %d. NVision contained the leak almost immediately, investors cheered the rapid response, and the stock is soaring." % [spy_name, solved_day]
		else:
			text = "You named %s as the leaker on day %d. The leak is stopped and NVision's secrets are safe, though the delay cost the company some confidence." % [spy_name, solved_day]
	elif case_state == "failed":
		text = "You never caught the leaker. %s released NVision's confidential files, the company's secrets are public, and the Board has fired you." % spy_name
	else:
		return ""
	if not wrong_accusations.is_empty():
		var names: Array = []
		for w in wrong_accusations:
			names.append(characters[w["id"]]["name"])
		text += " Along the way you wrongly accused %s, and those relationships are now front-page news." % ", ".join(PackedStringArray(names))
	return text
