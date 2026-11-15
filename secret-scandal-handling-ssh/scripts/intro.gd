extends Control

var images = [
	preload("res://.godot/imported/Midnight_Call_in_the_City-1.png-02ecc79bd96db0b85194b463320c4ae2.ctex"),
	preload("res://.godot/imported/Project_ECLIPSE__Unauthorized_Access-4.png-0566a7506376f793284785d0b29a69f0.ctex"),
	preload("res://.godot/imported/Midnight_ECLIPSE_Access_Investigation-2.png-07f077edd50e234d4a4c2b4f984eb85f.ctex"),
	preload("res://.godot/imported/Five_Suspects_One_Hidden_Conspiracy-3.png-5f533fc6f20f8fb30de538f82d7bfe19.ctex"),
	preload("res://.godot/imported/Johnson_Jengs_Project_Eclipse_Crisis-5.png-1d13f7a3004b2142f8842e43b1fe16ab.ctex"),
	preload("res://.godot/imported/Mission_Briefing__Project_Eclipse-6.png-7ca95c371e91369d45e7d06c2a5df857.ctex")
]

# current background img
var current = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func next():
	if current < images.size() - 1:
		current = current + 1
		$background.texture = images[current]
		
func _on_next_button_pressed() -> void:
	next()
	
