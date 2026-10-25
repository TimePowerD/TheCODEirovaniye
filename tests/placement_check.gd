extends SceneTree

const SpaceCheck := preload("res://scripts/swap_space_check.gd")
var game: Node

func _initialize() -> void:
	call_deferred("_check")

func _sync() -> void:
	await physics_frame
	await physics_frame

func _obstacle(position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.7, 0.6)
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.global_position = position
	return body

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	game = current_scene
	game.get_node("MainMenu")._start_game()
	var player = game.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(4, 0.92, 4)
	player.rotation = Vector3.ZERO
	var item = game.get_node("PickupTestItem")
	player._pick_up_item(item)
	player.camera_pivot.rotation.x = -atan(1.5 / 1.8)
	await _sync()
	player._set_placement_mode(true)
	assert(player.placement_valid and player.placement_preview.visible, "Free nearby floor was rejected")
	assert(player.placement_preview.material_override.albedo_color.g > 0.9)
	assert(player.camera_pivot.global_position.distance_to(player.placement_position) <= player.placement_distance)
	var surface_point: Vector3 = player.aim_ray.get_collision_point()
	# A shallow ray hits the floor far beyond the three-metre placement range.
	player.camera_pivot.rotation.x = -0.2
	player._update_placement_preview()
	assert(not player.placement_valid and not player.placement_preview.visible)
	assert(not player._place_held_item() and player.held_item == item)
	# A box beside the ray blocks the item's volume without hiding the floor.
	player.camera_pivot.rotation.x = -atan(1.5 / 1.8)
	var obstacle := _obstacle(surface_point + Vector3(0.45, 0.35, 0))
	await _sync()
	player._update_placement_preview()
	assert(not player.placement_valid and not player.placement_preview.visible)
	assert(not player._place_held_item() and player.held_item == item)
	obstacle.collision_layer = 1
	await _sync()
	player._update_placement_preview()
	assert(not player.placement_valid)
	obstacle.queue_free()
	await _sync()
	# The ray excludes the player, but the full volume check must include them.
	player.camera_pivot.rotation.x = -atan(1.5 / 0.4)
	player._update_placement_preview()
	assert(not player.placement_valid and not player.placement_preview.visible)
	player.camera_pivot.rotation.x = -atan(1.5 / 1.8)
	player._update_placement_preview()
	assert(player.placement_valid)
	# Occupying a previously valid location cannot bypass release-time checks.
	obstacle = _obstacle(surface_point + Vector3(0.45, 0.35, 0))
	await _sync()
	assert(not player._place_held_item() and player.held_item == item)
	obstacle.queue_free()
	await _sync()
	assert(player._place_held_item())
	assert(player.held_item == null and not player.placement_preview.visible)
	assert(SpaceCheck.can_place(item, item.global_transform))
	# Reparenting and hand shrink must not change the checked world-scale volume.
	var container := Node3D.new()
	game.add_child(container)
	container.rotation.y = 0.3
	container.scale = Vector3(1.2, 1.2, 1.2)
	item.reparent(container, true)
	item.scale = Vector3(1.5, 1.0, 0.7)
	var world_scale: Vector3 = item.global_basis.get_scale()
	player._pick_up_item(item)
	player.held_item.rotation.y = 0.4
	player._set_placement_mode(true)
	assert(player.placement_valid)
	var expected := Transform3D(player.placement_basis.scaled_local(world_scale), player.placement_position)
	assert(player._place_held_item())
	assert(item.global_transform.is_equal_approx(expected), "Released transform differs from validated transform")
	assert(SpaceCheck.can_place(item, item.global_transform))
	# A low offset secondary collider must also clear the supporting surface.
	var extra := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 0.3, 0.3)
	extra.shape = shape
	extra.position = Vector3(0.8, -0.4, 0)
	item.add_child(extra)
	player._pick_up_item(item)
	await _sync()
	player._set_placement_mode(true)
	assert(player.placement_valid, "Offset compound collider was placed into the floor")
	assert(player._place_held_item())
	assert(SpaceCheck.can_place(item, item.global_transform))
	# No active solid shapes means there is no safe volume to validate.
	player._pick_up_item(item)
	for owner_id in item.get_shape_owners():
		item.shape_owner_set_disabled(owner_id, true)
	player._set_placement_mode(true)
	assert(not player.placement_valid and not player._place_held_item())
	assert(player.held_item == item)
	print("PASS: placement distance, green marker, player/wall/object clearance, late obstacle, world scale, compound shapes and release recheck")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
