extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	var menu = game.get_node("MainMenu")
	var player = game.get_node("Player")
	menu._start_game()
	player.set_physics_process(false)
	var item = game.get_node("PickupTestItem")
	player._pick_up_item(item)
	for cycle in range(3):
		player._set_rotation_mode(true)
		player._set_rotation_axis(1)
		player.rotation_speed = 2.0
		player.e_hold_pending = true
		player.e_hold_elapsed = 0.2
		player._set_placement_mode(true)
		assert(player.rotation_mode and player.rotation_gizmo.visible)
		menu._show_pause_menu()
		assert(paused and not player.rotation_mode)
		assert(player.rotation_axis_index == -1 and is_zero_approx(player.rotation_speed))
		assert(not player.rotation_gizmo.visible)
		assert(not player.e_hold_pending and is_zero_approx(player.e_hold_elapsed))
		assert(not player.placement_mode and not player.placement_preview.visible)
		assert(player.held_item == item and item.get_parent() == player.hand_anchor)
		assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
		# R is released while gameplay input is paused, as in the reported bug.
		var release := InputEventKey.new()
		release.keycode = KEY_R
		Input.parse_input_event(release)
		await process_frame
		if cycle == 1:
			menu._show_pause_settings()
			await process_frame
		menu._resume_game()
		assert(not paused and not player.rotation_mode)
		assert(player.held_item == item)
		assert(player.is_processing_unhandled_input())
		assert(not player.is_physics_processing(), "Pause changed physics processing flags")
		var yaw: float = player.rotation.y
		player.apply_look(Vector2(30, 0))
		assert(not is_equal_approx(yaw, player.rotation.y), "Look did not recover after resume")
	# The same reset stops a physically grabbed object's angular velocity.
	player._drop_item()
	var box = game.get_node("SmallBox")
	player.held_object = box
	player.add_collision_exception_with(box)
	player._set_rotation_mode(true)
	player.rotation_speed = 1.0
	box.angular_velocity = Vector3(0, 2, 0)
	menu._show_pause_menu()
	assert(not player.rotation_mode and box.angular_velocity.is_zero_approx())
	menu._resume_game()
	assert(not player.rotation_mode)
	player._release_object()
	print("PASS: pause clears rotation/axis/speed/gizmo, E hold and placement; carried item and look survive resume/settings")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
