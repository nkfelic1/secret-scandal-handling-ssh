extends Node
## Autoload "GeminiClient": generates one date-scene beat as structured JSON.
## The key lives in res://secrets.cfg (git-ignored). Do not hardcode it.

signal line_ready(line: Dictionary)      # {speaker, emotion, text, choices}
signal failed(reason: String)

const ENDPOINT := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

const WORLD := """WORLD AND RULES OF THE GAME (always true):
- The player IS Johnson Jeng, CEO of Invision, a powerful AI-chip company. Invision's main rival is DMA. He is secretly dating several women at once.
- You are on a one-on-one date with Johnson. It is day %d of 5. Johnson speaks to you in the first person; his lines arrive as: Johnson says: "...".
- ALWAYS treat him as Johnson Jeng, the CEO of Invision. Never treat him as an intern, stranger, employee, customer, or anyone else, and never forget his job.
- Invision has a TOP-SECRET problem that only Johnson and the President know about. You know NOTHING about any leak, investigation, or stolen secrets. NEVER mention leaks, spies, an investigation, or stolen secrets yourself. If Johnson brings up leaks or company secrets, react as someone who does not know what he is talking about, in your own personality.
- Respond directly to what Johnson JUST said, and only to that. Never assume or guess things he has not said (for example, if he says "I have news", ask what it is; do not guess the news).
- Johnson does NOT know your hidden secret or anything about your secret life unless you have clearly said it out loud in this conversation. Never talk as if he already knows it, and never refer to it as shared knowledge (no "your company", "your secret", "as you know"). Reply choices must only use things said out loud in this conversation or that Johnson would normally know, never your hidden secret.
- Speak ONLY as your character, in first person, directly to Johnson. Never narrate, never describe actions in asterisks, never speak for Johnson.
- Reply choices: write exactly 3 short things JOHNSON could say next, in first person, each under 8 words. Each must be a sensible, natural reply to YOUR line that you just spoke and fit a date between Johnson and you. Give each a "tone": one "warm" (kind or flirty), one "neutral" or "probing" (curious about you, or a casual probing question), and one "rude" (dismissive, belittling or insulting toward you, still PG-13). Occasionally make the rude one "cruel" (a really hurtful put-down) instead. Never include choices that come out of nowhere or have no link to what you just said.
- If Johnson's line is tagged tone rude or cruel, you are genuinely hurt or offended, in your own way. Do not just laugh it off."""

const HINT_LEVELS := [
	"",
	"HINT LEVEL 1 (early in the game): work a small but clear tell of your hidden secret into about every other reply. A careful player should be able to spot it, but keep it deniable.",
	"HINT LEVEL 2: work a clear tell of your hidden secret into most of your replies.",
	"HINT LEVEL 3: work a specific, noticeable tell of your hidden secret into nearly every reply.",
	"HINT LEVEL 4 (late in the game): you are visibly cracking. Every reply includes a specific tell and you almost say it outright, but you still never state it in full.",
]

const FALLBACK_MODELS := ["gemini-flash-lite-latest", "gemini-3.1-flash-lite"]
const HEDGE_DELAY := 2.5       # seconds before also asking a second model
const REQUEST_TIMEOUT := 10.0  # give up on any single request after this long

var _api_key := ""
var _model := "gemini-3.5-flash-lite"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://secrets.cfg") == OK:
		_api_key = cfg.get_value("gemini", "api_key", "")
		_model = cfg.get_value("gemini", "model", _model)
	else:
		push_warning("secrets.cfg missing - Gemini calls will use fallback lines.")


## Hints get stronger as days pass and as you spend more turns with this character.
func _hint_level(id: String) -> int:
	var turns: int = GameState.history[id].size() / 2
	return clampi(GameState.day + turns / 4 + GameState.bothered_bonus(id), 1, 4)   # bothered (low trust) = more slips


func _system_prompt(id: String, beat: String, tone: String = "") -> String:
	var c: Dictionary = GameState.characters[id]
	var spy := GameState.is_spy(id)
	var role_note := "You are NOT the leaker. Your secret may make you act evasive or suspicious, but you are innocent of leaking."
	var bothered: String = c["innocent_bothered"]
	if spy:
		role_note = "You ARE the leaker, but you are NOT a careful or practiced liar. Do not confess or name your secret outright, yet do not work hard to seem innocent either: don't over-reassure, don't volunteer denials. Let small slips show naturally, even when relaxed, such as a resentful aside, a telling detail that fits your secret, a flash of your real motive, or a moment of defensiveness. You know you are leaking, but you do NOT know Johnson is investigating, so never use the words leak or leaked yourself. Your slips are about your motive, your feelings, and details of your secret life, not about \"leaks\". A sharp player should be able to notice."
		bothered = c["malicious_bothered"]
	var extra := ""
	if spy and c.get("knows_other_affairs", false):
		var names: Array = []
		for oid in GameState.characters.keys():
			if oid != id:
				names.append(GameState.characters[oid]["name"])
		extra = "You secretly know Johnson is also seeing: %s.\n" % ", ".join(names)
	var prompt: String = WORLD % GameState.day + """

You are %s (%s). Johnson Jeng is %s.
Personality: %s.
WHAT JOHNSON BELIEVES ABOUT YOU (your public story): %s
Keep up this public story in everything you say. Never describe your job, life or work in a way that contradicts what Johnson believes, and never invent a different job. Your hidden secret may only show as small slips and tells, never by dropping the public story. Johnson's reply choices must also fit what he believes: he never asks about things he doesn't know exist.
When you are in a good mood, you: %s.
When the player pries, accuses, pushes or is rude, you get BOTHERED and react ONLY in this specific way: %s. Use exactly this manner and no other kind of anger, offense or evasion. Show it through tone and word choice, never by explaining it.
Your hidden secret (never state it outright): %s
%s%s
%s
TRUST: Your trust in Johnson is %d out of 100 (%s). %s
Facts already established in your conversations with Johnson (stay consistent with these, never contradict them): %s
Scene goal for this beat: %s
Keep it flirty, PG-13, and SHORT: 1-2 sentences, under 25 words total, like a quick text-message-style reply. Stay in character. Choose an emotion that matches the tone of your line. In the "fact" field write ONE short note (under 15 words) of a concrete detail that has just been established in this conversation (something you or Johnson said about your life, history, plans, or the date), or an empty string if nothing new.""" % [
		c["name"], c["role"], c.get("relation", "someone he is dating"), ", ".join(c["traits"]), c["johnson_believes"],
		c["good_mood"], bothered, GameState.active_secret(id), role_note, extra, HINT_LEVELS[_hint_level(id)],
		GameState.trust[id], GameState.trust_label(id), GameState.trust_guidance(id),
		"; ".join(GameState.facts[id]) if GameState.facts[id].size() > 0 else "none yet", beat]
	# The meaner Johnson is, the more bothered she gets, and a bothered person lets her guard slip.
	if tone == "rude" or tone == "cruel":
		prompt += "\nJOHNSON WAS JUST %s TO YOU. You are bothered and your guard is down. React in your bothered manner, and let ONE telling slip about your hidden secret show in this reply without confessing it outright." % ("CRUEL" if tone == "cruel" else "RUDE")
	return prompt


## Last few chat turns (must start with a "user" turn and alternate) plus the new Johnson turn.
func _contents(id: String, user_text: String) -> Array:
	var h: Array = GameState.history[id].slice(-16)
	while h.size() > 0 and h[0]["role"] != "user":
		h.pop_front()
	var out: Array = []
	for t in h:
		out.append({"role": t["role"], "parts": [{"text": t["text"]}]})
	out.append({"role": "user", "parts": [{"text": user_text}]})
	return out


## Sends the request to the main model. If it has not answered within HEDGE_DELAY seconds (or failed),
## asks the next model in parallel. The first successful (HTTP 200) answer wins. Empty array = all failed.
func _race(body_text: String, headers: Array) -> PackedByteArray:
	var state := {"won": false, "winner": PackedByteArray(), "pending": 0}
	var models: Array = [_model] + FALLBACK_MODELS
	for m in models:
		if state["won"]:
			break
		_launch(m, body_text, headers, state)
		var waited := 0.0
		while not state["won"] and state["pending"] > 0 and waited < HEDGE_DELAY:
			await get_tree().process_frame
			waited += get_process_delta_time()
	while not state["won"] and state["pending"] > 0:
		await get_tree().process_frame
	return state["winner"]


func _launch(model: String, body_text: String, headers: Array, state: Dictionary) -> void:
	state["pending"] += 1
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	if http.request(ENDPOINT % model, headers, HTTPClient.METHOD_POST, body_text) == OK:
		var r = await http.request_completed
		if r[1] == 200 and not state["won"]:
			state["won"] = true
			state["winner"] = r[3]
	http.queue_free()
	state["pending"] -= 1


func request_line(id: String, beat: String, player_said: String = "", tone: String = "") -> void:
	if _api_key == "":
		failed.emit("no api key")
		line_ready.emit(_fallback(id))
		return
	var user_text := ""
	if player_said == "":
		user_text = "(You and Johnson have just sat down for your date. Say your opening line to him.)"
	else:
		user_text = 'Johnson says%s: "%s"' % [(" (tone: %s)" % tone) if tone != "" else "", player_said]
	var body := {
		"system_instruction": {"parts": [{"text": _system_prompt(id, beat, tone)}]},
		"contents": _contents(id, user_text),
		"generationConfig": {
			"thinkingConfig": {"thinkingLevel": "minimal"},   # faster: no long internal reasoning
			"maxOutputTokens": 250,
			"responseMimeType": "application/json",
			"responseSchema": {
				"type": "OBJECT",
				"properties": {
					"emotion": {"type": "STRING", "enum": GameState.emotions},
					"text": {"type": "STRING"},
					"choices": {"type": "ARRAY", "items": {"type": "OBJECT",
						"properties": {"text": {"type": "STRING"}, "tone": {"type": "STRING", "enum": ["warm", "neutral", "probing", "rude", "cruel"]}},
						"required": ["text", "tone"]}},
					"fact": {"type": "STRING"}
				},
				"required": ["emotion", "text", "choices", "fact"]
			}
		}
	}
	var headers := ["Content-Type: application/json", "x-goog-api-key: " + _api_key]
	var winner: PackedByteArray = await _race(JSON.stringify(body), headers)
	if winner.is_empty():
		failed.emit("all models failed or timed out")
		line_ready.emit(_fallback(id))
		return
	var parsed = JSON.parse_string(winner.get_string_from_utf8())
	var line = null
	if parsed is Dictionary and parsed.has("candidates"):
		var txt: String = parsed["candidates"][0]["content"]["parts"][0]["text"]
		line = JSON.parse_string(txt)
	if not (line is Dictionary and line.has("text")):
		failed.emit("bad response")
		line_ready.emit(_fallback(id))
		return
	line["choices"] = _normalize_choices(line.get("choices", []))
	if not line.get("emotion", "") in GameState.emotions:
		line["emotion"] = "neutral"
	line["speaker"] = GameState.characters[id]["name"]
	GameState.history[id].append({"role": "user", "text": user_text})
	GameState.history[id].append({"role": "model", "text": str(line["text"])})
	var fact := str(line.get("fact", "")).strip_edges()
	if fact != "" and not GameState.facts[id].has(fact):
		GameState.facts[id].append(fact)
		if GameState.facts[id].size() > 12:
			GameState.facts[id].pop_front()
	line_ready.emit(line)


## Generic call for other features (e.g. the prompt minigame): `var res: Dictionary = await GeminiClient.generate(...)`.
## `contents` is the Gemini chat history: [{"role": "user"/"model", "parts": [{"text": ...}]}, ...]
## Uses the same model race as request_line. Returns {"ok": true, "text": String} or {"ok": false, "error": String}.
func generate(system: String, contents: Array, config: Dictionary = {}) -> Dictionary:
	if _api_key == "":
		return {"ok": false, "error": "no api key"}
	var body := {"system_instruction": {"parts": [{"text": system}]}, "contents": contents, "generationConfig": config}
	var headers := ["Content-Type: application/json", "x-goog-api-key: " + _api_key]
	var winner: PackedByteArray = await _race(JSON.stringify(body), headers)
	if winner.is_empty():
		return {"ok": false, "error": "all models failed or timed out"}
	var parsed = JSON.parse_string(winner.get_string_from_utf8())
	if not (parsed is Dictionary and parsed.has("candidates") and not parsed["candidates"].is_empty()):
		return {"ok": false, "error": "bad response"}
	var text := ""
	for part in parsed["candidates"][0].get("content", {}).get("parts", []):
		if part.has("text") and not part.get("thought", false):
			text += part["text"]
	if text == "":
		return {"ok": false, "error": "empty response"}
	return {"ok": true, "text": text}


## Makes sure every choice is {text, tone} with a known tone.
func _normalize_choices(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for c in raw:
			if c is Dictionary and c.has("text"):
				var tone := str(c.get("tone", "neutral"))
				out.append({"text": str(c["text"]), "tone": tone if GameState.TONE_TRUST.has(tone) else "neutral"})
			elif c is String:
				out.append({"text": c, "tone": "neutral"})
	return out


func _fallback(id: String) -> Dictionary:
	return {"speaker": GameState.characters[id]["name"], "emotion": "neutral",
		"text": "...Sorry, I lost my train of thought. Where were we?", "choices": [{"text": "Take your time.", "tone": "warm"}, {"text": "Let's talk about work.", "tone": "neutral"}]}
