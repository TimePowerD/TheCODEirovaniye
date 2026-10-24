extends Node3D

func _ready() -> void:
	var game: Node = get_node("Game")
	var main_menu := game.get_node_or_null("MainMenu")
	if main_menu != null:
		main_menu.start_test_session()

	get_tree().paused = false
	call_deferred("_capture_mouse")

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
