extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var street := load("res://scenes/flashback_room.tscn").instantiate() as Node3D
	root.add_child(street)
	await physics_frame
	await physics_frame
	var space := street.get_world_3d().direct_space_state
	# Both pavements and the road must have continuous ground underfoot.
	for x in [-5.5, 0.0, 5.5]:
		for z in [3.0, -15.0, -35.0]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 2, z), Vector3(x, -2, z))
			var hit := space.intersect_ray(ray)
			assert(not hit.is_empty() and hit.collider == street.get_node("Ground"), "Street has a gap")
	for path in ["Houses/HouseLeft1", "Trees/TreeLeft1"]:
		var body := street.get_node(path) as StaticBody3D
		var center := body.global_position + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3(4, 0, 0), center)
		var hit := space.intersect_ray(ray)
		assert(not hit.is_empty() and hit.collider == body, "Scenery collision is missing")
	var boundary := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(23, 2, 0), Vector3(25, 2, 0)))
	assert(not boundary.is_empty(), "Street boundary is open")
	assert(street.get_node("Sun").light_cull_mask == 2)
	for mesh in street.find_children("*", "MeshInstance3D", true, false):
		assert(mesh.layers == 2, "Street mesh is outside the sunlight layer")
	print("PASS: street ground, house/tree collisions, boundary and lighting isolation")
	quit()
