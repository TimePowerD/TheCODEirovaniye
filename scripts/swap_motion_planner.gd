extends RefCounted

## Plans all moves in a private physics space; never mutates the live level.
const Geometry := preload("res://scripts/swap_space_check.gd")
const MAX_PUSH_DISTANCE := 2.0
const MAX_PUSHED_BODIES := 16
const MAX_DEPTH := 8
const MAX_OPERATIONS := 1200
const GAP := 0.004

var space: RID
var state: PhysicsDirectSpaceState3D
var ghosts: Dictionary = {}
var owners: Dictionary = {}
var originals: Dictionary = {}
var poses: Dictionary = {}
var local_shapes: Dictionary = {}
var fixed: Array[PhysicsBody3D] = []
var operations := 0
var reason := ""

static func create_plan(first: Node3D, second: Node3D, first_source: Transform3D, second_source: Transform3D) -> Dictionary:
	if not is_instance_valid(first) or not is_instance_valid(second) or first == second or not first is PhysicsBody3D or not second is PhysicsBody3D:
		return {"ok": false, "reason": "неподходящие цели обмена"}
	if first.get_world_3d() != second.get_world_3d():
		return {"ok": false, "reason": "цели находятся в разных пространствах"}
	var planner = new()
	planner.fixed.assign([first, second])
	planner._prepare(first, second, first_source, second_source)
	var result: Dictionary = planner._solve(first, second)
	planner._dispose()
	return result

func _prepare(first: PhysicsBody3D, second: PhysicsBody3D, first_source: Transform3D, second_source: Transform3D) -> void:
	space = PhysicsServer3D.space_create()
	var bodies := first.get_tree().root.find_children("*", "PhysicsBody3D", true, false)
	for target in [first, second]:
		if target not in bodies:
			bodies.append(target)
	for body in bodies:
		if body.is_queued_for_deletion() or body.get_world_3d() != first.get_world_3d() or body.collision_layer == 0:
			continue
		var entries: Array[Dictionary] = []
		for owner_id in body.get_shape_owners():
			if body.is_shape_owner_disabled(owner_id):
				continue
			for index in range(body.shape_owner_get_shape_count(owner_id)):
				entries.append({"shape": body.shape_owner_get_shape(owner_id, index), "local": body.shape_owner_get_transform(owner_id)})
		if entries.is_empty():
			continue
		var pose: Transform3D = body.global_transform
		if body == first:
			pose = first_source
		elif body == second:
			pose = second_source
		var ghost := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ghost, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(ghost, body.collision_layer)
		for entry in entries:
			PhysicsServer3D.body_add_shape(ghost, entry.shape.get_rid(), pose * entry.local)
		PhysicsServer3D.body_set_space(ghost, space)
		ghosts[body] = ghost
		owners[ghost] = body
		local_shapes[body] = entries
		originals[body] = pose
		poses[body] = pose
	state = PhysicsServer3D.space_get_direct_state(space)

func _dispose() -> void:
	for ghost in ghosts.values():
		PhysicsServer3D.free_rid(ghost)
	if space.is_valid():
		PhysicsServer3D.free_rid(space)

func _set_pose(body: PhysicsBody3D, pose: Transform3D) -> void:
	poses[body] = pose
	var entries: Array = local_shapes[body]
	for index in range(entries.size()):
		PhysicsServer3D.body_set_shape_transform(ghosts[body], index, pose * entries[index].local)

func _restore(snapshot: Dictionary) -> void:
	for body in snapshot:
		_set_pose(body, snapshot[body])

func _shapes(body: PhysicsBody3D, pose: Transform3D) -> Array[Dictionary]:
	return Geometry._shapes_for_transform(body, pose)

func _overlaps(body: PhysicsBody3D, pose: Transform3D) -> Array[PhysicsBody3D]:
	var result: Array[PhysicsBody3D] = []
	var shapes := _shapes(body, pose)
	for entry in shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = entry.transform
		query.collision_mask = 0xffffffff
		query.exclude = [ghosts[body]]
		var hits := state.intersect_shape(query, 128)
		if hits.size() >= 128:
			reason = "слишком много соседних коллизий"
			operations = MAX_OPERATIONS
		for hit in hits:
			var other: PhysicsBody3D = owners[hit.rid]
			if other in result:
				continue
			var excluded: Array[RID] = []
			for ghost in ghosts.values():
				if ghost != hit.rid:
					excluded.append(ghost)
			if not Geometry._clear(state, shapes, excluded):
				result.append(other)
	return result

func _movable(body: PhysicsBody3D) -> bool:
	return body is RigidBody3D and body not in fixed and not body.freeze and body.get("physics_enabled") != false and not body.has_meta("object_swap_locked") and not _shapes(body, poses[body]).is_empty()

func _support(shape: Shape3D, direction: Vector3) -> float:
	if shape is BoxShape3D:
		return shape.size.dot(direction.abs()) * 0.5
	if shape is SphereShape3D:
		return shape.radius * direction.length()
	if shape is CylinderShape3D:
		return shape.height * absf(direction.y) * 0.5 + shape.radius * Vector2(direction.x, direction.z).length()
	if shape is CapsuleShape3D:
		return shape.radius * direction.length() + maxf(shape.height * 0.5 - shape.radius, 0.0) * absf(direction.y)
	var extent := -INF
	if shape is ConvexPolygonShape3D:
		for point in shape.points:
			extent = maxf(extent, point.dot(direction))
	return extent

func _bottom(body: PhysicsBody3D, pose: Transform3D) -> float:
	var bottom := INF
	for entry in _shapes(body, pose):
		var transform: Transform3D = entry.transform
		bottom = minf(bottom, transform.origin.y - _support(entry.shape, transform.basis.transposed() * Vector3.DOWN))
	return bottom

func _destination(moving: PhysicsBody3D, recipient: PhysicsBody3D) -> Transform3D:
	var destination: Transform3D = originals[moving]
	destination.origin = originals[recipient].origin
	var bottom := _bottom(recipient, originals[recipient])
	var position: Vector3 = originals[recipient].origin
	var query := PhysicsRayQueryParameters3D.create(Vector3(position.x, bottom + 0.04, position.z), Vector3(position.x, bottom - 0.15, position.z), 0xffffffff)
	query.exclude = [ghosts[fixed[0]], ghosts[fixed[1]]]
	var hit := state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.7:
		destination.origin.y += hit.position.y + GAP - _bottom(moving, destination)
	return destination

func _solve(first: PhysicsBody3D, second: PhysicsBody3D) -> Dictionary:
	if not ghosts.has(first) or not ghosts.has(second) or _shapes(first, originals[first]).is_empty() or _shapes(second, originals[second]).is_empty():
		return {"ok": false, "reason": "нет поддерживаемого физического объёма"}
	var first_destination := _destination(first, second)
	var second_destination := _destination(second, first)
	_set_pose(first, first_destination)
	_set_pose(second, second_destination)
	for target in fixed:
		for neighbor in _overlaps(target, poses[target]):
			if not _movable(neighbor):
				return {"ok": false, "reason": "неподвижное препятствие: %s" % neighbor.name}
			if not _push_out(neighbor, target):
				return {"ok": false, "reason": reason if not reason.is_empty() else "соседние предметы зажаты и не могут отодвинуться"}
	if operations >= MAX_OPERATIONS:
		return {"ok": false, "reason": "превышен безопасный лимит проверки соседних предметов"}
	var moves: Array[Dictionary] = []
	for body in poses:
		if body not in fixed and not poses[body].is_equal_approx(originals[body]):
			moves.append({"body": body, "transform": poses[body]})
	return {"ok": true, "first": first_destination, "second": second_destination, "pushes": moves}

func _push_out(body: RigidBody3D, cause: PhysicsBody3D) -> bool:
	var radial: Vector3 = poses[body].origin - poses[cause].origin
	radial.y = 0.0
	var directions: Array[Vector3] = []
	for direction in [radial.normalized(), Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
		if not direction.is_zero_approx() and direction not in directions:
			directions.append(direction)
	var snapshot := poses.duplicate()
	for direction in directions:
		if direction.is_zero_approx():
			continue
		for step in range(1, 21):
			if operations >= MAX_OPERATIONS:
				reason = "не удалось найти безопасное оттеснение в пределах лимита проверки"
				_restore(snapshot)
				return false
			_restore(snapshot)
			var candidate: Transform3D = snapshot[body]
			candidate.origin += direction * step * 0.1
			var fits := true
			var intersections := _overlaps(body, candidate)
			for target in fixed:
				if target in intersections:
					fits = false
			if fits and _move(body, candidate, []):
				return true
	_restore(snapshot)
	if reason.is_empty():
		reason = "не найден безопасный путь оттеснения соседних предметов в пределах 2 м"
	return false

func _move(body: RigidBody3D, destination: Transform3D, chain: Array) -> bool:
	operations += 1
	if operations >= MAX_OPERATIONS or chain.size() >= MAX_DEPTH or body in chain:
		return false
	var motion: Vector3 = destination.origin - poses[body].origin
	var total: Vector3 = destination.origin - originals[body].origin
	if total.length() > MAX_PUSH_DISTANCE:
		return false
	if (body.axis_lock_linear_x and absf(motion.x) > 0.001) or (body.axis_lock_linear_z and absf(motion.z) > 0.001):
		return false
	var moved := 0
	for candidate in poses:
		if candidate not in fixed and not poses[candidate].is_equal_approx(originals[candidate]):
			moved += 1
	if moved >= MAX_PUSHED_BODIES:
		return false
	var original_pose: Transform3D = poses[body]
	var active_chain := chain.duplicate()
	active_chain.append(body)
	for attempt in range(12):
		operations += 1
		if operations >= MAX_OPERATIONS:
			return false
		var unsafe := 1.0
		for entry in _shapes(body, original_pose):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = entry.shape
			query.transform = entry.transform
			query.transform.origin.y += GAP
			query.motion = motion
			query.collision_mask = 0xffffffff
			query.exclude = [ghosts[body], ghosts[fixed[0]], ghosts[fixed[1]]]
			var fractions := state.cast_motion(query)
			if fractions.size() == 2:
				unsafe = minf(unsafe, fractions[1])
		if unsafe >= 0.999:
			_set_pose(body, destination)
			if _overlaps(body, destination).is_empty():
				return true
			_set_pose(body, original_pose)
			return false
		var contact := original_pose
		contact.origin += motion * minf(1.0, unsafe + 0.02 / maxf(motion.length(), 0.001))
		var blockers := _overlaps(body, contact)
		var pushed := false
		for blocker in blockers:
			if blocker in fixed:
				continue
			if not _movable(blocker):
				return false
			var next: Transform3D = poses[blocker]
			next.origin += motion.normalized() * (motion.length() * (1.0 - unsafe) + 0.05)
			if not _move(blocker, next, active_chain):
				return false
			pushed = true
		if not pushed:
			return false
	return false
