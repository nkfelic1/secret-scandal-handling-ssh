extends Control
## Ending screen: reveals the hidden trustmeter score and any punishment, plus how each woman feels about Johnson.
## Layout lives in ending.tscn. The numbers come from GameState.ending_report().

const OUTCOME_TITLES := {
	"clean": "You treated them well",
	"reputation": "Your reputation takes a hit",
	"scandal": "SCANDAL",
	"alone": "ALONE",
}

## The leak investigation outcome takes priority over the trustmeter title.
const CASE_TITLES := {
	"solved": "LEAK STOPPED",
	"failed": "FIRED",
}


func _ready() -> void:
	var r: Dictionary = GameState.ending_report()
	%Title.text = CASE_TITLES.get(r["case_state"], OUTCOME_TITLES.get(r["outcome"], "The end"))
	%Rating.text = "Trustmeter: %+d  -  %s" % [r["trustmeter"], r["rating"]]
	var text := ""
	if r["case_summary"] != "":
		var color := "#8fe3a0" if r["case_state"] == "solved" else "#ff7a7a"
		text += "[center][color=%s]%s[/color][/center]\n\n" % [color, r["case_summary"]]
	if r["punishment"] != "":
		text += "[center]%s[/center]" % r["punishment"]
	else:
		text += "[center]You were kind to the people who trusted you, and it shows.[/center]"
	text += "\n\n[center][color=#9a8aa8]Replies picked: %d warm, %d neutral, %d probing, %d rude, %d cruel[/color][/center]" % [
		r["tone_counts"]["warm"], r["tone_counts"]["neutral"], r["tone_counts"]["probing"], r["tone_counts"]["rude"], r["tone_counts"]["cruel"]]
	%Punishment.text = text
	for id in GameState.characters.keys():
		var c: Dictionary = GameState.characters[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name := Label.new()
		name.text = c["name"]
		name.custom_minimum_size = Vector2(120, 0)
		row.add_child(name)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(500, 20)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.value = GameState.trust[id]
		bar.modulate = Color.from_hsv(clampf(GameState.trust[id] / 100.0, 0.0, 1.0) * 0.33, 0.65, 1.0)
		row.add_child(bar)
		var state := Label.new()
		if GameState.is_accused(id):
			state.text = "Wrongly accused"
		elif GameState.dumped[id]:
			state.text = "Left you"
		else:
			state.text = GameState.trust_label(id)
		row.add_child(state)
		%TrustList.add_child(row)
	%NewRunButton.pressed.connect(func():
		GameState.new_run()
		get_tree().change_scene_to_file("res://scenes/date_select.tscn"))
	%MenuButton.pressed.connect(func():
		GameState.new_run()
		get_tree().change_scene_to_file("res://scenes/home.tscn"))
