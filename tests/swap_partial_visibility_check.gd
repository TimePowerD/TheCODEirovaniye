extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("_check")

func _sync() -> void:
	await physics_frame
	await physics_frame

func _box(position: Vector3, size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	body.collision_layer = 2
	body.add_to_group("swappable")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	body.add_child(mesh)
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
	player.global_position = Vector3(0, 19.42, 8)
	player.rotation = Vector3.ZERO
	player.camera_pivot.rotation = Vector3.ZERO
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	var target := _box(Vector3(0, 20, 0), Vector3(4, 4, 4))
	var other := _box(Vector3(-4, 20, 0), Vector3.ONE)
	var wall := _box(Vector3(0, 20, 4), Vector3(1.2, 6, 0.2))
	wall.remove_from_group("swappable")
	wall.collision_layer = 1
	await _sync()
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target.global_position, 3, [player.get_rid()])
	assert(player.get_world_3d().direct_space_state.intersect_ray(ray).collider == wall)
	assert(player._is_swap_target_visible(target), "Visible edges were rejected because center is hidden")
	player.selected_target = target
	player.hovered_target = other
	player.swap_duration = 0.05
	player._handle_swap_click()
	assert(player.swap_in_progress, "Partial visibility did not allow actual swap")
	await create_timer(0.35).timeout
	assert(target.global_position.x == -4 and other.global_position.x == 0)
	target.global_position = Vector3(0, 20, 0)
	other.global_position = Vector3(-20, 20, 0)
	# A wider wall hides every part, and must still block selection.
	wall.get_child(0).shape.size.x = 6
	wall.get_child(1).mesh.size.x = 6
	await _sync()
	assert(not player._is_swap_target_visible(target), "Fully occluded model was accepted")
	wall.queue_free()
	await _sync()
	# The center is outside the camera, but part of the model is on-screen.
	var screen_size := root.get_visible_rect().size
	target.global_position = camera.project_position(Vector2(screen_size.x + 40, screen_size.y * 0.5), 8)
	await _sync()
	assert(not camera.is_position_in_frustum(target.global_position))
	assert(player._is_swap_target_visible(target), "Visible viewport-edge fragment was rejected")
	target.global_position = camera.global_position + camera.global_basis.z * 5
	await _sync()
	assert(not player._is_swap_target_visible(target), "Model behind camera was accepted")
	# An offset mesh/collider must use model bounds rather than the root origin.
	target.global_position = Vector3(60, 20, 0)
	target.get_child(0).position.x = -60
	target.get_child(1).position.x = -60
	await _sync()
	assert(not camera.is_position_in_frustum(target.global_position))
	assert(player._is_swap_target_visible(target), "Offset visible model was rejected")
	target.get_child(1).hide()
	assert(not player._is_swap_target_visible(target), "Hidden mesh was accepted")
	target.get_child(1).show()
	var old_mask := camera.cull_mask
	camera.cull_mask = 1
	target.get_child(1).layers = 2
	assert(not player._is_swap_target_visible(target), "Camera-hidden layer was accepted")
	camera.cull_mask = old_mask
	target.queue_free()
	await _sync()
	# Rounded geometry: the bounding box must not count as a visible surface.
	var sphere := _box(Vector3(0, 20, 0), Vector3(4, 4, 4))
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 2
	sphere.get_child(0).shape = sphere_shape
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 2
	sphere_mesh.height = 4
	sphere.get_child(1).mesh = sphere_mesh
	wall = _box(Vector3(0, 20, 4), Vector3(1.2, 6, 0.2))
	wall.remove_from_group("swappable")
	await _sync()
	assert(player._is_swap_target_visible(sphere), "Visible sphere fragment was rejected")
	wall.get_child(0).shape.size.x = 6
	wall.get_child(1).mesh.size.x = 6
	await _sync()
	assert(not player._is_swap_target_visible(sphere), "Bounds-only visibility bypassed full obstruction")
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 2
	cylinder_shape.height = 4
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 2
	cylinder_mesh.bottom_radius = 2
	cylinder_mesh.height = 4
	sphere.get_child(0).shape = cylinder_shape
	sphere.get_child(1).mesh = cylinder_mesh
	wall.get_child(0).shape.size.x = 1.2
	wall.get_child(1).mesh.size.x = 1.2
	await _sync()
	assert(player._is_swap_target_visible(sphere), "Visible cylinder fragment was rejected")
	wall.get_child(0).shape.size.x = 6
	wall.get_child(1).mesh.size.x = 6
	await _sync()
	assert(not player._is_swap_target_visible(sphere), "Fully hidden cylinder was accepted")
	print("PASS: partially occluded box/sphere/cylinder, viewport edge, offset model, actual swap, full obstruction, hidden mesh/layer and behind-camera rejection")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
