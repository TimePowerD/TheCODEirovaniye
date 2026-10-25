extends RefCounted

## Permit only the tiny contact penetration used by the physics solver at rest.
const CONTACT_TOLERANCE := 0.002

static func _shapes_at(body: PhysicsBody3D, destination: Vector3) -> Array[Dictionary]:
	var future := body.global_transform
	future.origin = destination
	return _shapes_for_transform(body, future)

static func _shapes_for_transform(body: PhysicsBody3D, future: Transform3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		for index in range(body.shape_owner_get_shape_count(owner_id)):
			var shape := body.shape_owner_get_shape(owner_id, index)
			if shape is ConcavePolygonShape3D or shape is HeightMapShape3D or shape is WorldBoundaryShape3D or shape is SeparationRayShape3D:
				return [] # Shape queries require a supported solid volume.
			result.append({"shape": shape, "transform": future * body.shape_owner_get_transform(owner_id)})
	return result

static func _clear(state: PhysicsDirectSpaceState3D, shapes: Array[Dictionary], excluded: Array[RID]) -> bool:
	for entry in shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = entry.transform
		query.collision_mask = 0xffffffff
		query.exclude = excluded
		query.collide_with_areas = false
		query.margin = 0.0
		var contacts := state.collide_shape(query, 128)
		# Refuse saturated results rather than risk missing another penetration.
		if contacts.size() >= 256:
			return false
		for index in range(0, contacts.size(), 2):
			if contacts[index].distance_squared_to(contacts[index + 1]) > CONTACT_TOLERANCE * CONTACT_TOLERANCE:
				return false
	return true

static func can_place(body: PhysicsBody3D, future: Transform3D) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var shapes := _shapes_for_transform(body, future)
	if shapes.is_empty():
		return false
	var excluded: Array[RID] = [body.get_rid()]
	return _clear(body.get_world_3d().direct_space_state, shapes, excluded)

static func can_swap(first: Node3D, second: Node3D, first_destination: Vector3, second_destination: Vector3) -> bool:
	if not is_instance_valid(first) or not is_instance_valid(second) or not first is PhysicsBody3D or not second is PhysicsBody3D:
		return false
	if first.get_world_3d() != second.get_world_3d():
		return false
	if first == second:
		return false
	var first_shapes := _shapes_at(first, first_destination)
	var second_shapes := _shapes_at(second, second_destination)
	if first_shapes.is_empty() or second_shapes.is_empty():
		return false
	var excluded: Array[RID] = [first.get_rid(), second.get_rid()]
	for player in first.get_tree().get_nodes_in_group("player"):
		if player is PhysicsBody3D:
			excluded.append(player.get_rid())
	var state := first.get_world_3d().direct_space_state
	if not _clear(state, first_shapes, excluded) or not _clear(state, second_shapes, excluded):
		return false
	# Check the future pair against each other, including offset/compound shapes.
	# An isolated static space avoids moving the real objects during validation.
	var space := PhysicsServer3D.space_create()
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	for entry in second_shapes:
		PhysicsServer3D.body_add_shape(body, entry.shape.get_rid(), entry.transform)
	PhysicsServer3D.body_set_space(body, space)
	var empty_exclusion: Array[RID] = []
	var pair_clear := _clear(PhysicsServer3D.space_get_direct_state(space), first_shapes, empty_exclusion)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return pair_clear
