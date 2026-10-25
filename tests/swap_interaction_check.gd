extends SceneTree

var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_check")

func _sync() -> void:
	await physics_frame
	await physics_frame

func _aim(target: Node3D) -> void:
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	camera.look_at(target.global_position, Vector3.UP)
	player.aim_ray.force_raycast_update()
	assert(player.aim_ray.get_collider() == target, "Test target is occluded")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	game.get_node("MainMenu")._start_game()
	player = game.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(4, 0.92, 4)
	player.rotation = Vector3.ZERO
	player.camera_pivot.rotation = Vector3.ZERO
	var first = game.get_node("SmallBox")
	var second = game.get_node("SwapTestObject")
	var other = game.get_node("PickupTestItem")
	first.add_to_group("carryable")
	for body in [first, second, other]:
		body.freeze = true
	first.global_position = Vector3(3, 1.2, 1.8)
	second.global_position = Vector3(5, 1.2, 1.8)
	other.global_position = Vector3(6.3, 1.2, 3.3)
	await _sync()
	player.swap_duration = 0.3
	assert(player._start_swap(first, second))
	_aim(first)
	player._try_grab_object()
	player._try_pickup_item()
	player._pick_up_item(first)
	assert(player.held_object == null and player.held_item == null)
	assert(first.get_parent() == game and first.collision_layer == 2)
	player._set_rotation_mode(true)
	assert(not player.rotation_mode)
	# The same player cannot begin a different interaction during the effect.
	_aim(other)
	player._try_grab_object()
	player._try_pickup_item()
	player._pick_up_item(other)
	assert(player.held_object == null and player.held_item == null)
	assert(other.get_parent() == game)
	await create_timer(0.6).timeout
	assert(not player.swap_in_progress)
	assert(not first.has_meta("object_swap_locked") and not second.has_meta("object_swap_locked"))
	_aim(first)
	player._try_grab_object()
	assert(player.held_object == first, "Grab remained locked after success")
	assert(not player._start_swap(first, second), "Swap took an object out of a grab")
	player._release_object()
	player._try_pickup_item()
	assert(player.held_item == first, "Pickup remained locked after success")
	assert(not player._start_swap(first, second))
	player._drop_item()
	# Object-level locks also protect direct calls when no local swap is running.
	other.set_meta("object_swap_locked", true)
	player._pick_up_item(other)
	assert(player.held_item == null and other.get_parent() == game)
	other.remove_meta("object_swap_locked")
	# Cancellation must release both locks too.
	first.freeze = true
	first.global_position = Vector3(3, 1.2, 1.8)
	second.global_position = Vector3(5, 1.2, 1.8)
	other.global_position = Vector3(-5, 0.5, 4)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2, 2)
	second.get_node("CollisionShape3D").shape = shape
	player.camera_pivot.get_node("Camera3D").rotation = Vector3.ZERO
	await _sync()
	assert(player._start_swap(first, second))
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var obstacle_shape := BoxShape3D.new()
	obstacle_shape.size = Vector3(0.3, 1, 1)
	collision.shape = obstacle_shape
	obstacle.add_child(collision)
	game.add_child(obstacle)
	obstacle.global_position = Vector3(3.75, 1.2, 1.8)
	await create_timer(0.5).timeout
	assert(not player.swap_in_progress and first.global_position.x == 3)
	assert(not first.has_meta("object_swap_locked") and not second.has_meta("object_swap_locked"))
	obstacle.queue_free()
	await _sync()
	_aim(first)
	player._try_grab_object()
	assert(player.held_object == first, "Grab remained locked after cancellation")
	player._release_object()
	print("PASS: swap blocks grab/pickup/rotation/direct pickup; inverse guard and success/cancel unlocks")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
