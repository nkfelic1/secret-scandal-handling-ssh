extends Node
## Autoload "GeminiClient": generates one date-scene beat as structured JSON.
## The key lives in res://secrets.cfg (git-ignored). Do not hardcode it.

signal line_ready(line: Dictionary)      # {speaker, emotion, text, choices}
signal failed(reason: String)

const ENDPOINT := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

var _api_key := ""
var _model := "gemini-3.1-flash-lite"
var _http: HTTPRequest


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://secrets.cfg") == OK:
		_api_key = cfg.get_value("gemini", "api_key", "")
		_model = cfg.get_value("gemini", "model", _model)
	else:
		push_warning("secrets.cfg missing - Gemini calls will use fallback lines.")
	_http = HTTPRequest.new()
	add_child(_http)


func _system_prompt(id: String, beat: String) -> String:
	var c: Dictionary = GameState.characters[id]
	var role_note := "You are NOT the leaker. Your secret may make you act evasive or suspicious, but you are innocent of leaking."
	if GameState.is_spy(id):
		role_note = "You ARE the leaker. Never confess. Let hints slip only through behavior and small slips."
	return """You are %s in a dating-sim mystery. The player is %s, a CEO who is dating several people and trying to find out which one is leaking company secrets.
Personality: %s.
Your hidden secret (never state it outright): %s
%s
Scene goal for this beat: %s
What you remember about the player so far: %s
Keep it flirty, PG-13, and SHORT: 1-2 sentences, under 25 words total, like a quick text-message-style reply. Each reply choice must be under 8 words. Stay in character. Choose an emotion that matches the tone of your line.""" % [
		c["name"], GameState.player_name, ", ".join(c["traits"]),
		GameState.active_secret(id), role_note, beat,
		GameState.memory[id] if GameState.memory[id] != "" else "nothing yet"]


func request_line(id: String, beat: String, player_said: String = "") -> void:
	if _api_key == "":
		failed.emit("no api key")
		line_ready.emit(_fallback(id))
		return
	var body := {
		"system_instruction": {"parts": [{"text": _system_prompt(id, beat)}]},
		"contents": [{"role": "user", "parts": [{"text": player_said if player_said != "" else "(the scene begins)"}]}],
		"generationConfig": {
			"thinkingConfig": {"thinkingLevel": "minimal"},   # faster: no long internal reasoning
			"maxOutputTokens": 250,
			"responseMimeType": "application/json",
			"responseSchema": {
				"type": "OBJECT",
				"properties": {
					"emotion": {"type": "STRING", "enum": GameState.emotions},
					"text": {"type": "STRING"},
					"choices": {"type": "ARRAY", "items": {"type": "STRING"}}
				},
				"required": ["emotion", "text", "choices"]
			}
		}
	}
	var headers := ["Content-Type: application/json", "x-goog-api-key: " + _api_key]
	var result = null
	var code := 0
	for attempt in 3:                       # retry on temporary overload (503) / rate limit (429)
		var err := _http.request(ENDPOINT % _model, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			failed.emit("request error %d" % err)
			line_ready.emit(_fallback(id))
			return
		result = await _http.request_completed
		code = result[1]
		if code != 503 and code != 429:
			break
		await get_tree().create_timer(1.5 * (attempt + 1)).timeout
	if code != 200:
		failed.emit("http %d" % code)
		line_ready.emit(_fallback(id))
		return
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	var line = null
	if parsed is Dictionary and parsed.has("candidates"):
		var txt: String = parsed["candidates"][0]["content"]["parts"][0]["text"]
		line = JSON.parse_string(txt)
	if not (line is Dictionary and line.has("text")):
		failed.emit("bad response")
		line_ready.emit(_fallback(id))
		return
	if not line.get("emotion", "") in GameState.emotions:
		line["emotion"] = "neutral"
	line["speaker"] = GameState.characters[id]["name"]
	line_ready.emit(line)


func _fallback(id: String) -> Dictionary:
	return {"speaker": GameState.characters[id]["name"], "emotion": "neutral",
		"text": "...Sorry, I lost my train of thought. Where were we?", "choices": ["Take your time.", "Let's talk about work."]}
