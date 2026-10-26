extends SceneTree
## Rebuild the editable forest scene: godot --headless --path . --script tools/build_forest.gd

const MODELS := "res://assets/models/citymodels realism/GLB format/"
const TREE_TYPES := ["tree-pine-large", "tree-large"]
const TRAIL_WIDTH := 3.2
var forest: Node3D
var rng := RandomNumberGenerator.new()
var trail: Curve3D
var tree_positions: Array[Vector3] = []

func _initialize() -> void:
	call_deferred("_build")

func _attach(parent: Node, child: Node, name_: String) -> Node:
	child.name = name_
	parent.add_child(child)
	child.owner = forest
	return child

func _group(name_: String) -> Node3D:
	return _attach(forest, Node3D.new(), name_) as Node3D

func _material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 1.0
	material.texture_repeat = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _build() -> void:
	rng.seed = 20261025
	forest = Node3D.new()
	forest.name = "ForestRoom"
	forest.set_meta("trail_width", TRAIL_WIDTH)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(0.86, 0.92, 0.77)
	sun.light_cull_mask = 4
	sun.layers = 4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	_attach(forest, sun, "ForestSun")
	_ground()
	_build_trail()
	_trees()
	_shrubs()
	_rocks()
	_arrival()
	_boundaries()
	forest.set_meta("tree_count", tree_positions.size())
	var packed := PackedScene.new()
	assert(packed.pack(forest) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/forest_room.tscn") == OK)
	print("BUILT FOREST: %d trees, %.1f m winding trail" % [tree_positions.size(), trail.get_baked_length()])
	forest.free()
	quit()

func _ground() -> void:
	var ground := _attach(forest, StaticBody3D.new(), "Ground") as StaticBody3D
	ground.position = Vector3(0, -0.25, -85)
	var shape := BoxShape3D.new()
	shape.size = Vector3(128, 0.5, 220)
	var collision := _attach(ground, CollisionShape3D.new(), "Collision") as CollisionShape3D
	collision.shape = shape
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-64, 0.25, -110), Vector3(64, 0.25, -110),
		Vector3(64, 0.25, 110), Vector3(-64, 0.25, 110),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(32, 0), Vector2(32, 55), Vector2(0, 55)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 3, 0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := _material(Color(0.38, 0.47, 0.32), load(MODELS + "Textures/grass.png"))
	mesh.surface_set_material(0, material)
	var visual := _attach(ground, MeshInstance3D.new(), "ForestFloor") as MeshInstance3D
	visual.mesh = mesh
	visual.layers = 4
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_trail() -> void:
	var controls: Array[Vector3] = [
		Vector3(0, 0, 10), Vector3(0, 0, -11), Vector3(-9, 0, -31),
		Vector3(-14, 0, -49), Vector3(4, 0, -71), Vector3(14, 0, -89),
		Vector3(-5, 0, -111), Vector3(-15, 0, -130),
		Vector3(5, 0, -150), Vector3(2, 0, -171),
	]
	trail = Curve3D.new()
	trail.bake_interval = 0.5
	for index in range(controls.size()):
		var previous: Vector3 = controls[maxi(index - 1, 0)]
		var next: Vector3 = controls[mini(index + 1, controls.size() - 1)]
		var tangent := (next - previous) * 0.25
		trail.add_point(controls[index], -tangent, tangent)
	var paths := _group("WindingTrail")
	paths.set_meta("centerline", controls)
	paths.set_meta("length", trail.get_baked_length())
	var shoulder := _attach(paths, MeshInstance3D.new(), "LeafyEdges") as MeshInstance3D
	shoulder.mesh = _trail_mesh(TRAIL_WIDTH + 1.4, 0.022)
	shoulder.material_override = _material(Color(0.31, 0.27, 0.18))
	shoulder.layers = 4
	shoulder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface := _attach(paths, MeshInstance3D.new(), "DirtPath") as MeshInstance3D
	surface.mesh = _trail_mesh(TRAIL_WIDTH, 0.03)
	surface.material_override = _material(Color(0.76, 0.66, 0.5), load(MODELS + "Textures/dirt.png"))
	surface.layers = 4
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paths.set_meta("source_texture", MODELS + "Textures/dirt.png")

func _trail_mesh(width: float, elevation: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var length := trail.get_baked_length()
	var steps := int(ceil(length / 1.2))
	for index in range(steps + 1):
		var distance := length * index / steps
		var center := trail.sample_baked(distance)
		var before := trail.sample_baked(maxf(distance - 0.5, 0.0))
		var after := trail.sample_baked(minf(distance + 0.5, length))
		var direction := (after - before).normalized()
		var right := direction.cross(Vector3.UP).normalized()
		for side in [-1.0, 1.0]:
			vertices.append(center + right * side * width * 0.5 + Vector3.UP * elevation)
			normals.append(Vector3.UP)
			uv.append(Vector2((side + 1.0) * width * 0.25, distance * 0.5))
		if index < steps:
			var offset := index * 2
			indices.append_array(PackedInt32Array([offset, offset + 2, offset + 1, offset + 1, offset + 2, offset + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _distance_to_trail(point: Vector2) -> float:
	var closest := INF
	var length := trail.get_baked_length()
	for step in range(int(length / 3.0) + 1):
		var center := trail.sample_baked(minf(step * 3.0, length))
		closest = minf(closest, point.distance_to(Vector2(center.x, center.z)))
	return closest

func _store_multimesh_instances(mesh: MultiMesh, poses: Array) -> void:
	# The headless renderer ignores set_instance_transform(), so write the
	# serializable 3D buffer directly in RenderingServer's row-major order.
	var data := PackedFloat32Array()
	data.resize(poses.size() * 12)
	for index in range(poses.size()):
		var pose: Transform3D = poses[index]
		var basis := pose.basis
		var offset := index * 12
		data[offset] = basis.x.x
		data[offset + 1] = basis.y.x
		data[offset + 2] = basis.z.x
		data[offset + 3] = pose.origin.x
		data[offset + 4] = basis.x.y
		data[offset + 5] = basis.y.y
		data[offset + 6] = basis.z.y
		data[offset + 7] = pose.origin.y
		data[offset + 8] = basis.x.z
		data[offset + 9] = basis.y.z
		data[offset + 10] = basis.z.z
		data[offset + 11] = pose.origin.z
	mesh.instance_count = poses.size()
	mesh.buffer = data
	mesh.custom_aabb = AABB(Vector3(-64, -1, -190), Vector3(128, 22, 220))

func _trees() -> void:
	var trees := _group("Trees")
	var transforms := [[], []]
	for row in range(39):
		for column in range(24):
			var x := -59.0 + column * 5.1 + rng.randf_range(-1.15, 1.15)
			var z := -183.0 + row * 5.1 + rng.randf_range(-1.15, 1.15)
			if _distance_to_trail(Vector2(x, z)) < 5.3:
				continue
			var position_ := Vector3(x, 0, z)
			tree_positions.append(position_)
			var kind := rng.randi_range(0, TREE_TYPES.size() - 1)
			var scale_ := rng.randf_range(5.8, 8.4)
			var pose := Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_), position_)
			transforms[kind].append(pose)
			var trunk := _attach(trees, StaticBody3D.new(), "Trunk_%03d" % tree_positions.size()) as StaticBody3D
			trunk.position = position_
			var collision := _attach(trunk, CollisionShape3D.new(), "Collision") as CollisionShape3D
			var shape := CylinderShape3D.new()
			shape.radius = 0.38
			shape.height = 3.3
			collision.position.y = 1.65
			collision.shape = shape
	for kind in range(TREE_TYPES.size()):
		var asset := load(MODELS + TREE_TYPES[kind] + ".glb") as PackedScene
		var instance := asset.instantiate()
		var source := instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = source.mesh
		_store_multimesh_instances(mesh, transforms[kind])
		var visual := _attach(trees, MultiMeshInstance3D.new(), TREE_TYPES[kind]) as MultiMeshInstance3D
		visual.multimesh = mesh
		visual.layers = 4
		visual.set_meta("source_model", MODELS + TREE_TYPES[kind] + ".glb")
		instance.free()

func _shrubs() -> void:
	var group := _group("Undergrowth")
	var asset := load(MODELS + "tree-shrub.glb") as PackedScene
	var instance := asset.instantiate()
	var source := instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var poses: Array[Transform3D] = []
	for index in range(270):
		var x := rng.randf_range(-60, 60)
		var z := rng.randf_range(-183, 13)
		if _distance_to_trail(Vector2(x, z)) < 3.5:
			continue
		var scale_ := rng.randf_range(3.0, 5.4)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_), Vector3(x, 0, z)))
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = source.mesh
	_store_multimesh_instances(mesh, poses)
	var visual := _attach(group, MultiMeshInstance3D.new(), "Shrubs") as MultiMeshInstance3D
	visual.multimesh = mesh
	visual.layers = 4
	visual.set_meta("source_model", MODELS + "tree-shrub.glb")
	instance.free()

func _rocks() -> void:
	var group := _group("ForestRocks")
	var material := _material(Color(0.34, 0.38, 0.33))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = material
	var poses: Array[Transform3D] = []
	for index in range(85):
		var x := rng.randf_range(-57, 57)
		var z := rng.randf_range(-179, 10)
		if _distance_to_trail(Vector2(x, z)) < 3.2:
			continue
		var size := rng.randf_range(0.5, 1.4)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(size, size * 0.35, size * 0.72)), Vector3(x, 0.17, z)))
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = sphere
	_store_multimesh_instances(mesh, poses)
	var visual := _attach(group, MultiMeshInstance3D.new(), "Rocks") as MultiMeshInstance3D
	visual.multimesh = mesh
	visual.layers = 4

func _arrival() -> void:
	var arrival := _attach(forest, Marker3D.new(), "Arrival") as Marker3D
	# Place the player well inside the forest, centered on the winding trail.
	arrival.position = trail.sample_baked(43.0) + Vector3.UP * 0.92
	var forward := trail.sample_baked(48.0) - trail.sample_baked(43.0)
	arrival.basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	var finish := _attach(forest, Marker3D.new(), "TrailEnd") as Marker3D
	finish.position = Vector3(2, 0, -171)

func _boundaries() -> void:
	var boundaries := _group("Boundaries")
	for side in [-1.0, 1.0]:
		var east_west := _attach(boundaries, StaticBody3D.new(), "SideBoundary") as StaticBody3D
		east_west.position = Vector3(side * 64, 2, -85)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, 4, 220)
		var collision := _attach(east_west, CollisionShape3D.new(), "Collision") as CollisionShape3D
		collision.shape = shape
		var north_south := _attach(boundaries, StaticBody3D.new(), "EndBoundary") as StaticBody3D
		north_south.position = Vector3(0, 2, -85 + side * 110)
		var end_shape := BoxShape3D.new()
		end_shape.size = Vector3(128, 4, 1)
		var end_collision := _attach(north_south, CollisionShape3D.new(), "Collision") as CollisionShape3D
		end_collision.shape = end_shape
