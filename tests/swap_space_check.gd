extends SceneTree

const SpaceCheck := preload("res://scripts/swap_space_check.gd")
var game: Node

func _body(name: String, position: Vector3, size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = name
	body.freeze = true
	body.add_to_group("swappable")
	body.collision_layer = 2
	body.collision_mask = 3
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.global_position = position
	return body

func _sync() -> void:
	await physics_frame
	await physics_frame

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	game = current_scene
	game.get_node("MainMenu")._start_game()
	var player = game.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 19.42, 8)
	player.rotation = Vector3.ZERO
	player.camera_pivot.rotation = Vector3.ZERO
	var first := _body("SmallTarget", Vector3(-2, 20, 0), Vector3.ONE)
	var second := _body("LargeTarget", Vector3(2, 20, 0), Vector3(2, 2, 2))
	await _sync()
	assert(SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	var obstacle := _body("Obstacle", Vector3(-1.15, 20, 0), Vector3(0.4, 3, 1))
	await _sync()
	assert(player._is_swap_target_visible(first) and player._is_swap_target_visible(second))
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	assert(not SpaceCheck.can_swap(second, first, first.global_position, second.global_position))
	player.selected_target = first
	player.hovered_target = second
	player._handle_swap_click()
	assert(not player.swap_in_progress and player.selected_target == first)
	assert(player.interaction_hint.text == player.SWAP_SPACE_ERROR)
	assert(first.global_position == Vector3(-2, 20, 0) and second.global_position == Vector3(2, 20, 0))
	# A wall on layer 1 must block just like a separate physical object on layer 2.
	obstacle.collision_layer = 1
	await _sync()
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	obstacle.queue_free()
	await _sync()
	# The player is not excluded from occupancy queries.
	player.global_position = Vector3(-0.9, 20, 0)
	await _sync()
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	player.global_position = Vector3(0, 19.42, 8)
	await _sync()
	# Rotation and scale belong to each object's volume, not the destination.
	second.rotation.y = PI / 4.0
	second.scale = Vector3(1.3, 1, 1)
	obstacle = _body("RotatedObstacle", Vector3(-0.5, 20, 0), Vector3(0.3, 3, 1))
	await _sync()
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	obstacle.queue_free()
	second.rotation = Vector3.ZERO
	second.scale = Vector3.ONE
	# Offset shapes can intersect the other target only AFTER exchanging origins.
	second.global_position = Vector3(0, 20, 0)
	second.get_child(0).position.x = 2.0
	await _sync()
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position), "Future pair overlap was ignored")
	second.get_child(0).position = Vector3.ZERO
	second.global_position = Vector3(2, 20, 0)
	# Every enabled shape in a compound body must fit.
	var extra := CollisionShape3D.new()
	extra.shape = BoxShape3D.new()
	extra.position.x = -1.3
	second.add_child(extra)
	obstacle = _body("CompoundObstacle", Vector3(-3.4, 20, 0), Vector3(0.5, 1, 1))
	await _sync()
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	extra.disabled = true
	await _sync()
	assert(SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	extra.queue_free()
	obstacle.queue_free()
	await _sync()
	# A late obstacle aborts the swap and restores the original transforms/state.
	player.swap_duration = 0.3
	assert(player._start_swap(first, second))
	assert(first.has_meta("object_swap_locked") and second.has_meta("object_swap_locked"))
	obstacle = _body("LateObstacle", Vector3(-1.15, 20, 0), Vector3(0.4, 3, 1))
	await create_timer(0.45).timeout
	assert(not player.swap_in_progress)
	assert(first.global_position == Vector3(-2, 20, 0) and second.global_position == Vector3(2, 20, 0))
	assert(not first.has_meta("object_swap_locked") and not second.has_meta("object_swap_locked"))
	assert(first.freeze and second.freeze)
	obstacle.queue_free()
	await _sync()
	# Success preserves full-size collision bodies through the visual pop.
	player.swap_duration = 0.05
	first.freeze = false
	first.gravity_scale = 0.0
	assert(player._start_swap(first, second))
	assert(first.freeze)
	await create_timer(0.1).timeout
	assert(first.global_position == Vector3(2, 20, 0) and second.global_position == Vector3(-2, 20, 0))
	assert(first.scale == Vector3.ONE and second.scale == Vector3.ONE)
	assert(not first.freeze and second.freeze)
	first.freeze = true
	# Touching the supporting floor must not make all grounded swaps impossible.
	first.global_position = Vector3(-2, 0.5, 4)
	second.global_position = Vector3(2, 1.0, 4)
	await _sync()
	assert(not SpaceCheck.can_swap(first, first, first.global_position, first.global_position))
	assert(not SpaceCheck.can_swap(first, second, second.global_position, first.global_position), "Large target would penetrate the floor")
	# Same-height resting boxes fit without penetrating the floor.
	second.get_child(0).shape = BoxShape3D.new()
	second.global_position.y = 0.5
	await _sync()
	assert(SpaceCheck.can_swap(first, second, second.global_position, first.global_position))
	await process_frame
	print("PASS: swap occupancy, both bodies, walls, player, scale/rotation, compound shapes, future pair, late abort, floor and body scale")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
