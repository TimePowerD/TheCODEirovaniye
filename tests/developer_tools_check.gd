extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	var menu = game.get_node("MainMenu")
	var tools = game.get_node("DeveloperTools")
	var player = game.get_node("Player")
	var tutorial = game.get_node("Tutorial")
	tools.toggle()
	assert(not tools.opened, "Developer menu opened before game start")
	menu._start_game()
	await physics_frame
	tools.toggle()
	assert(tools.opened and player.is_physics_processing())
	assert(player.has_meta("developer_tools_open") and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/developer-menu-preview.png")
	assert(tools.markers.size() == 4 and tools.cutscenes.size() == 1)
	assert(not game.get_node("LocationTransition").request_transition(true))
	var move := InputEventKey.new()
	move.keycode = KEY_D
	move.pressed = true
	Input.parse_input_event(move)
	var before: Vector3 = player.global_position
	await create_timer(0.3).timeout
	move = InputEventKey.new()
	move.keycode = KEY_D
	Input.parse_input_event(move)
	assert(player.global_position.distance_to(before) > 0.2, "F1 stopped player movement")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(700, 300)
	tools._unhandled_input(right)
	var yaw: float = player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50, 0)
	tools._unhandled_input(motion)
	assert(not is_equal_approx(player.rotation.y, yaw), "F1 mouse look did not turn player")
	right = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	tools._input(right)
	assert(not tools.looking and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	player.rotation = Vector3.ZERO
	player.global_position = Vector3(4, 0.92, 4)
	await physics_frame
	var cube = tools.spawn_object(false)
	assert(cube != null and cube.is_in_group("swappable"))
	await physics_frame
	var second = tools.spawn_object(false)
	assert(second == null or cube.global_position.distance_to(second.global_position) >= 1.0, "Spawner created overlapping objects")
	await physics_frame
	var target = second if second != null else cube
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_camera_3d().unproject_position(target.global_position)
	tools._unhandled_input(click)
	assert(tools.selected_object == target and not tools.delete_button.disabled)
	assert(not tools.previous_overlays.is_empty())
	var count_before: int = tools.objects.size()
	tools.delete_selected()
	assert(tools.objects.size() == count_before - 1)
	assert(tools.selected_object == null and tools.delete_button.disabled)
	if target != cube:
		assert(is_instance_valid(cube) and not cube.is_queued_for_deletion(), "Deleted unselected object")
	tools.select_at_screen_position(root.get_camera_3d().unproject_position(game.get_node("LargeCylinder").global_position))
	assert(tools.selected_object == null and tools.delete_button.disabled, "Selected level geometry for deletion")
	tools.clear_objects()
	await physics_frame
	await process_frame
	var item = tools.spawn_object(true)
	assert(item != null and item.is_in_group("carryable"))
	tools.toggle_markers()
	assert(tools.debug_meshes.size() == 4)
	tools.toggle_markers()
	assert(tools.debug_meshes.is_empty())
	tools.close()
	assert(player.is_physics_processing() and player.is_processing_unhandled_input())
	assert(not player.has_meta("developer_tools_open"))
	tutorial.restart()
	player.gameplay_action.emit(&"pickup")
	assert(not tutorial.completed, "Out-of-order action completed tutorial")
	assert(tutorial.ACTIONS.size() == 20)
	for action in tutorial.ACTIONS:
		player.gameplay_action.emit(action)
		assert(tutorial.completed)
		tutorial._process(1.3)
	assert(tutorial.step == tutorial.ACTIONS.size())
	tools.restart_tutorial()
	assert(tutorial.step == 0)
	tools.skip_tutorial()
	assert(tutorial.step == tutorial.ACTIONS.size())
	var cutscene = game.get_node("DeveloperCameraPreview")
	var camera := root.get_camera_3d()
	cutscene.play()
	assert(cutscene.running and not player.is_physics_processing())
	assert(not game.get_node("LocationTransition").request_transition(true))
	tools.toggle()
	assert(not tools.opened, "Developer UI interrupted cutscene")
	await create_timer(0.2).timeout
	cutscene.stop()
	assert(not cutscene.running and player.is_physics_processing())
	assert(root.get_camera_3d() == camera)
	cutscene.play()
	await create_timer(4.2).timeout
	assert(not cutscene.running and not player.has_meta("cutscene_active"))
	tools.clear_objects()
	assert(tools.objects.is_empty())
	var disabled := CanvasLayer.new()
	disabled.set_script(load("res://scripts/developer_tools.gd"))
	disabled.enabled = false
	root.add_child(disabled)
	await process_frame
	assert(not is_instance_valid(disabled))
	print("PASS: developer UI, safe spawning, markers, tutorial actions, cutscene start/stop, camera and disable flag")
	quit()
