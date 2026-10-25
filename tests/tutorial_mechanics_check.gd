extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	var player = game.get_node("Player")
	var tutorial = game.get_node("Tutorial")
	var tools = game.get_node("DeveloperTools")
	game.get_node("MainMenu")._start_game()
	await create_timer(0.2).timeout
	assert(tutorial.ACTIONS.size() == 4)
	player.gameplay_action.emit(&"pickup")
	player.gameplay_action.emit(&"rotate")
	assert(not tutorial.completed and tutorial.pending_actions.is_empty())
	player.global_position = Vector3(4, 0.92, 4)
	_key(KEY_W, true)
	await create_timer(0.45).timeout
	_key(KEY_W, false)
	assert(tutorial.completed and tutorial.step == 0)
	_key(KEY_SPACE, true)
	await create_timer(0.1).timeout
	_key(KEY_SPACE, false)
	assert(tutorial.pending_actions == [&"jump"], "Fast jump was lost during walk checkmark")
	var item = game.get_node("PickupTestItem")
	player._pick_up_item(item)
	assert(tutorial.pending_actions == [&"jump", &"pickup"])
	player._drop_item()
	player.set_physics_process(false)
	player.global_position = Vector3(4, 0.92, 4)
	player.rotation = Vector3.ZERO
	player.camera_pivot.rotation = Vector3.ZERO
	var first = game.get_node("SmallBox")
	var second = game.get_node("SwapTestObject")
	first.freeze = true
	second.freeze = true
	first.global_position = Vector3(3, 1.2, 1)
	second.global_position = Vector3(5, 1.2, 1)
	item.global_position = Vector3(-5, 0.5, 4)
	await physics_frame
	await physics_frame
	player.hovered_target = first
	player._handle_swap_click()
	assert(tutorial.pending_actions.size() == 2, "First selection completed swap lesson")
	player.hovered_target = second
	player.swap_duration = 0.05
	player._handle_swap_click()
	assert(player.swap_in_progress)
	await create_timer(0.1).timeout
	assert(tutorial.pending_actions == [&"jump", &"pickup", &"swap"], "Fast successful swap was lost")
	await create_timer(4.8).timeout
	assert(tutorial.step == 4 and not tutorial.panel.visible)
	# Restart clears completed/pending tasks; grabbing also counts as taking.
	tutorial.restart()
	assert(tutorial.step == 0 and tutorial.pending_actions.is_empty())
	tutorial._on_action(&"walk")
	tutorial._on_action(&"jump")
	tutorial._process(2.5)
	assert(tutorial.step == 2 and not tutorial.completed)
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	camera.look_at(first.global_position, Vector3.UP)
	player.aim_ray.force_raycast_update()
	player._try_grab_object()
	assert(player.held_object == first and tutorial.completed, "Grab did not satisfy taking task")
	player._release_object()
	assert(tutorial.pending_actions.is_empty(), "Release added an unwanted lesson")
	tutorial.restart()
	tools.toggle()
	player.gameplay_action.emit(&"walk")
	assert(not tutorial.completed)
	tools.close()
	tutorial._on_action(&"walk")
	tutorial._on_action(&"jump")
	assert(not tutorial.pending_actions.is_empty())
	tutorial.skip()
	assert(tutorial.step == 4 and tutorial.pending_actions.is_empty() and not tutorial.completed)
	tutorial.restart()
	assert(tutorial.step == 0 and not tutorial.completed and tutorial.pending_actions.is_empty())
	print("PASS: four basic tutorial tasks, real rapid walk/jump/pickup/swap, grab alternative, ignored extras, restart/skip and developer gating")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
