extends SceneTree

const SwapMotionPlanner := preload("res://scripts/swap_motion_planner.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	game.get_node("MainMenu")._start_game()
	var player = game.get_node("Player")
	var sphere = game.get_node("MediumSphere")
	var cube = game.get_node("SwapTestObject3")
	assert(
		player._room_anchor_for_position(sphere.global_position)
		== player._room_anchor_for_position(cube.global_position),
		"Puzzle-room sphere and cube were assigned to different rooms"
	)
	var plan := SwapMotionPlanner.create_plan(
		sphere, cube, sphere.global_transform, cube.global_transform
	)
	assert(plan.ok, "Laboratory sphere/cube swap space rejected: %s" % plan.get("reason", ""))
	print("PASS: laboratory sphere and cube share the puzzle-room volume")
	quit()
