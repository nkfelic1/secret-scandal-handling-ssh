extends Node
## Autoload "GameState": holds the run's hidden truth. The spy is chosen HERE in code, never by the AI.

const CHARACTERS_PATH := "res://data/characters.json"

var emotions: Array = []
var characters: Dictionary = {}
var spy_id: String = ""
var day: int = 1
var dates_left: int = 5
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


func _ready() -> void:
	_load_characters()
	new_run()


func _load_characters() -> void:
	var f := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	emotions = data["emotions"]
	characters = data["characters"]


func new_run() -> void:
	randomize()
	var ids := characters.keys()
	spy_id = ids[randi() % ids.size()]
	day = 1
	dates_left = 5
	clues_seen.clear()
	for id in ids:
		memory[id] = ""
		history[id] = []
		facts[id] = []
		affection[id] = 0
		trust[id] = START_TRUST
		dumped[id] = false
		rude_streak[id] = 0
	trustmeter = 0
	tone_counts = {"warm": 0, "neutral": 0, "probing": 0, "rude": 0, "cruel": 0}


func is_spy(id: String) -> bool:
	return id == spy_id


func active_secret(id: String) -> String:
	var c: Dictionary = characters[id]
	return c["malicious_secret"] if is_spy(id) else c["innocent_secret"]


## Returns the "guess who the leaker is" result.
func accuse(id: String) -> bool:
	return is_spy(id)


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
	trustmeter += delta                                  # raw points: kind adds, mean subtracts
	if tone == "rude" or tone == "cruel":
		rude_streak[id] += 1
		if rude_streak[id] >= 2:
			delta -= 2 * mini(rude_streak[id] - 1, 3)   # being nasty again and again hurts a little more each time
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
		"dumped": gone, "tone_counts": tone_counts.duplicate()}
