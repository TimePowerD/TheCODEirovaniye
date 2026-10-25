extends SceneTree

const Planner := preload("res://scripts/swap_motion_planner.gd")
const SpaceCheck := preload("res://scripts/swap_space_check.gd")
var game: Node

func _initialize() -> void:
	call_deferred("_check")

func _sync() -> void:
	await physics_frame
	await physics_frame

func _box(position: Vector3, size: Vector3, movable: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(preload("res://scripts/physics_object.gd"))
	body.add_to_group("swappable")
	body.add_to_group("swapAble")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.freeze = not movable
	body.gravity_scale = 0
	body.global_position = position
	return body

func _plan(first: PhysicsBody3D, second: PhysicsBody3D) -> Dictionary:
	return Planner.create_plan(first, second, first.global_transform, second.global_transform)

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	game = current_scene
	game.get_node("MainMenu")._start_game()
	var player = game.get_node("Player")
	player.set_physics_process(false)
	game.get_node("PickupTestItem").global_position = Vector3(-5, 0.5, 4)
	var sphere = game.get_node("MediumSphere")
	var cylinder = game.get_node("LargeCylinder")
	sphere.freeze = true
	cylinder.freeze = true
	await _sync()
	var sphere_source: Transform3D = sphere.global_transform
	var cylinder_source: Transform3D = cylinder.global_transform
	var plan := _plan(sphere, cylinder)
	assert(plan.ok, "Starting sphere/cylinder swap rejected: %s" % plan.get("reason", ""))
	assert(absf(plan.first.origin.y - 0.804) < 0.01)
	assert(absf(plan.second.origin.y - 1.204) < 0.01)
	assert(plan.first.origin.x == cylinder_source.origin.x and plan.second.origin.x == sphere_source.origin.x)
	player.swap_duration = 0.05
	assert(player._start_swap(sphere, cylinder))
	await create_timer(0.35).timeout
	assert(absf(sphere.global_position.y - 0.804) < 0.01 and absf(cylinder.global_position.y - 1.204) < 0.01)
	assert(SpaceCheck.can_place(sphere, sphere.global_transform) and SpaceCheck.can_place(cylinder, cylinder.global_transform))
	sphere.freeze = false
	cylinder.freeze = false
	await create_timer(0.3).timeout
	assert(_plan(sphere, cylinder).ok)
	assert(player._start_swap(sphere, cylinder))
	await create_timer(0.35).timeout
	assert(sphere.global_position.y > 0.79 and cylinder.global_position.y > 1.19)
	assert(not sphere.freeze and not cylinder.freeze)
	# Airborne objects keep center-based exchange instead of seeking a remote floor.
	player.global_position = Vector3(0, 19.42, 8)
	var first := _box(Vector3(-2, 20, 0), Vector3.ONE, false)
	var second := _box(Vector3(2, 20, 0), Vector3(2, 2, 2), false)
	await _sync()
	plan = _plan(first, second)
	assert(plan.ok and is_equal_approx(plan.first.origin.y, 20.0))
	var neighbor := _box(Vector3(-1.15, 20, 0), Vector3(0.4, 0.4, 0.4), true)
	await _sync()
	var neighbor_source: Vector3 = neighbor.global_position
	plan = _plan(first, second)
	assert(plan.ok and plan.pushes.size() == 1, "Free dynamic neighbor should be pushed")
	assert(neighbor.global_position == neighbor_source, "Planning mutated live object")
	assert(plan.pushes[0].transform.origin.x > neighbor_source.x)
	var chain := _box(Vector3(-0.65, 20, 0), Vector3(0.4, 0.4, 0.4), true)
	await _sync()
	plan = _plan(first, second)
	assert(plan.ok and plan.pushes.size() == 2, "Dynamic chain did not move")
	# Apply the verified plan through real gameplay, not just the helper.
	assert(player._start_swap(first, second))
	await create_timer(0.35).timeout
	assert(first.global_position.x == 2 and second.global_position.x == -2)
	assert(neighbor.global_position.x > neighbor_source.x and chain.global_position.x > -0.65)
	assert(SpaceCheck.can_place(first, first.global_transform) and SpaceCheck.can_place(second, second.global_transform))
	# Reset and verify that freezing or locking the neighbor is not ignored.
	first.global_position = Vector3(-2, 20, 0)
	second.global_position = Vector3(2, 20, 0)
	neighbor.global_position = neighbor_source
	chain.queue_free()
	neighbor.freeze = true
	await _sync()
	assert(not _plan(first, second).ok, "Frozen obstacle was treated as movable")
	neighbor.freeze = false
	neighbor.axis_lock_linear_x = true
	neighbor.axis_lock_linear_z = true
	await _sync()
	assert(not _plan(first, second).ok, "Linear axis locks were ignored")
	neighbor.axis_lock_linear_x = false
	neighbor.axis_lock_linear_z = false
	# A chain pinned between a wall and the destination cannot pass through it.
	chain = _box(Vector3(-0.65, 20, 0), Vector3(0.4, 0.4, 0.4), true)
	neighbor.axis_lock_linear_z = true
	chain.axis_lock_linear_z = true
	var wall := _box(Vector3(-0.2, 20, 0), Vector3(0.2, 2, 2), false)
	await _sync()
	var neighbor_before: Transform3D = neighbor.global_transform
	var chain_before: Transform3D = chain.global_transform
	plan = _plan(first, second)
	assert(not plan.ok, "Pinned chain moved through wall")
	assert(neighbor.global_transform.is_equal_approx(neighbor_before) and chain.global_transform.is_equal_approx(chain_before))
	wall.queue_free()
	chain.queue_free()
	await _sync()
	# A clear endpoint beyond a thin wall is not a valid push path.
	wall = _box(Vector3(-0.9, 20, 0), Vector3(0.04, 2, 2), false)
	await _sync()
	assert(not _plan(first, second).ok, "Push tunneled through a thin wall")
	neighbor.axis_lock_linear_z = false
	assert(_plan(first, second).ok, "An available sideways escape path was ignored")
	wall.queue_free()
	neighbor.queue_free()
	await _sync()
	# The player remains an immovable blocker.
	player.global_position = Vector3(-0.9, 20, 0)
	await _sync()
	assert(not _plan(first, second).ok, "Planner pushed the player")
	print("PASS: grounded sphere/cylinder, airborne centers, dynamic neighbor/chain, atomic planning, frozen/axis-locked obstacles, pinned wall and player")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	for sound in game.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	await create_timer(0.1).timeout
	quit()
