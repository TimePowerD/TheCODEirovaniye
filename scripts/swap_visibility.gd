extends RefCounted

## Sample the model's bounds and their clipped screen rectangle. A bounding-box
## overlap alone never grants visibility: a ray must actually hit the target.
static func _hits_target(target: Node3D, camera: Camera3D, origin: Vector3, end: Vector3, mask: int, excluded: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, end, mask, excluded)
	var hit := target.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and camera.is_position_in_frustum(hit.position) and (hit.collider == target or target.is_ancestor_of(hit.collider))

static func _visible_point(target: Node3D, camera: Camera3D, point: Vector3, mask: int, excluded: Array[RID]) -> bool:
	if not camera.is_position_in_frustum(point):
		return false
	var origin := camera.project_ray_origin(camera.unproject_position(point))
	return _hits_target(target, camera, origin, point + (point - origin).normalized() * 0.01, mask, excluded)

static func is_visible(target: Node3D, camera: Camera3D, mask: int, excluded: Array[RID]) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree() or not target.is_in_group("swappable"):
		return false
	var meshes := target.find_children("*", "MeshInstance3D", true, false)
	if target is MeshInstance3D:
		meshes.append(target)
	# Collider-only debug objects retain their original center-based behavior.
	if meshes.is_empty():
		return _visible_point(target, camera, target.global_position, mask, excluded)
	var viewport := camera.get_viewport().get_visible_rect()
	for mesh in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree() or (mesh.layers & camera.cull_mask) == 0 or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var bounds: AABB = mesh.get_aabb()
		var transform: Transform3D = mesh.global_transform
		var center := transform * bounds.get_center()
		if _visible_point(target, camera, center, mask, excluded):
			return true
		var screen_min := Vector2(INF, INF)
		var screen_max := Vector2(-INF, -INF)
		var max_distance := 0.0
		var front := false
		var near_clipped := false
		for index in range(8):
			var corner := transform * bounds.get_endpoint(index)
			max_distance = maxf(max_distance, camera.global_position.distance_to(corner))
			var local := camera.global_transform.affine_inverse() * corner
			if local.z >= -camera.near:
				near_clipped = true
				continue
			front = true
			var screen := camera.unproject_position(corner)
			screen_min = screen_min.min(screen)
			screen_max = screen_max.max(screen)
		if not front:
			continue
		var rectangle := viewport if near_clipped else Rect2(screen_min, screen_max - screen_min).intersection(viewport)
		if not rectangle.has_area():
			continue
		# Faces/edges give rounded models useful rays even when the center is hidden.
		for x in range(3):
			for y in range(3):
				for z in range(3):
					if x == 1 and y == 1 and z == 1:
						continue
					var local_point := bounds.position + bounds.size * Vector3(x, y, z) * 0.5
					if _visible_point(target, camera, transform * local_point, mask, excluded):
						return true
		# Clip to the viewport first: the visible sliver can be much smaller than
		# the model, and every corner/center may be outside the screen.
		for x in range(7):
			for y in range(7):
				var uv := Vector2((x + 0.5) / 7.0, (y + 0.5) / 7.0)
				var screen := rectangle.position + rectangle.size * uv
				var origin := camera.project_ray_origin(screen)
				var end := origin + camera.project_ray_normal(screen) * minf(camera.far, max_distance + 1.0)
				if _hits_target(target, camera, origin, end, mask, excluded):
					return true
	return false
