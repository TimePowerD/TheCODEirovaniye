extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	game.get_node("MainMenu")._start_game()
	var player = game.get_node("Player")
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
	await physics_frame
	await physics_frame
	assert(player._is_swap_target_visible(first) and player._is_swap_target_visible(second))
	var first_start: Vector3 = first.global_position
	var second_start: Vector3 = second.global_position
	# First selection remains remembered when it is moved behind the camera.
	player.hovered_target = first
	player._handle_swap_click()
	first.global_position = Vector3(4, 1.2, 7)
	await physics_frame
	player.hovered_target = second
	player._handle_swap_click()
	assert(not player.swap_in_progress and player.selected_target == first)
	assert(second.global_position == second_start)
	assert(is_equal_approx(player.swap_error_remaining, 1.5))
	assert(player.interaction_hint.text == player.SWAP_VISIBILITY_ERROR)
	# Frustum check rejects an unobstructed object to the side as well.
	first.global_position = Vector3(-5, 1.2, 3)
	await physics_frame
	assert(not player._start_swap(first, second))
	first.global_position = first_start
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 3, 0.3) # Hide the whole model, not just its center.
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	wall.global_position = Vector3(3.5, 1.4, 2)
	await physics_frame
	await physics_frame
	assert(not player._start_swap(first, second), "Swapped through wall hiding first target")
	assert(first.global_position == first_start and second.global_position == second_start)
	# Transparent-looking geometry still blocks the physical visibility ray.
	wall.global_position = Vector3(4.5, 1.4, 2)
	await physics_frame
	await physics_frame
	assert(not player._start_swap(first, second), "Swapped through obstruction hiding second target")
	wall.queue_free()
	await physics_frame
	await physics_frame
	first.remove_from_group("swappable")
	assert(not player._start_swap(first, second), "Non-swappable target was accepted")
	first.add_to_group("swappable")
	assert(not player._start_swap(first, first))
	assert(not player._start_swap(null, second))
	# Deletion between clicks must not access the stale hover or selection.
	var removed := Node3D.new()
	game.add_child(removed)
	player.selected_target = removed
	player.hovered_target = removed
	removed.free()
	player._handle_swap_click()
	player.hovered_target = second
	player._handle_swap_click()
	assert(player.selected_target == second and not player.swap_in_progress)
	# Retry the originally rejected pair when both targets are visible again.
	player.selected_target = first
	player.hovered_target = second
	player.swap_duration = 0.05
	player._handle_swap_click()
	assert(player.swap_in_progress and player.selected_target == null)
	assert(is_zero_approx(player.swap_error_remaining))
	await create_timer(0.35).timeout
	assert(not player.swap_in_progress)
	assert(first.global_position.is_equal_approx(second_start))
	assert(second.global_position.is_equal_approx(first_start))
	# Error hint expires in gameplay time without changing the usual hints.
	assert(not player._start_swap(null, second))
	player.set_physics_process(true)
	await create_timer(1.6).timeout
	assert(is_zero_approx(player.swap_error_remaining))
	assert(player.interaction_hint.text != player.SWAP_VISIBILITY_ERROR)
	print("PASS: swap frustum, both occlusion rays, invalid targets, preserved selection, retry and hint expiry")
	quit()
