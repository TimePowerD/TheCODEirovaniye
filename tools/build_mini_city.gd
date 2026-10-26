extends SceneTree
## Rebuild the editable city scene: godot --headless --path . --script tools/build_mini_city.gd
const URBAN_MODELS := "res://assets/models/citymodels realism/GLB format/"
# The lens fits inside the downward-facing underside of detail-light-single.glb.
const LAMP_LENS_CENTER := Vector3(0, 0.9088, -0.165)
const LAMP_LENS_SIZE := Vector3(0.05, 0.008, 0.088)
var city: Node3D
var shapes: Dictionary = {}
var materials: Dictionary = {}
var house_meshes: Dictionary = {}
var house_count := 0
var grass: StandardMaterial3D
var white: StandardMaterial3D

func _initialize() -> void:
	call_deferred("_build")

func _attach(parent: Node, node: Node) -> Node:
	parent.add_child(node)
	node.owner = city
	return node

func _container(parent: Node, name_: String) -> Node3D:
	var node := Node3D.new()
	node.name = name_
	_attach(parent, node)
	return node

func _own(node: Node) -> void:
	node.owner = city
	for child in node.get_children():
		_own(child)

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != ancestor:
		pose = cursor.transform * pose
		cursor = cursor.get_parent() as Node3D
	return pose

func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _relative(mesh, model) * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _model(parent: Node3D, path: String, name_: String, position_: Vector3, size: Vector3) -> Node3D:
	var scene := load(path) as PackedScene
	var model := scene.instantiate() as Node3D
	model.name = name_
	model.scene_file_path = ""
	parent.add_child(model)
	_own(model)
	model.set_meta("source_model", path)
	var bounds := _bounds(model)
	var factor := Vector3(size.x / bounds.size.x, size.y / maxf(bounds.size.y, 0.00001), size.z / bounds.size.z)
	model.scale = factor
	model.position = position_ - Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source != null:
				if not materials.has(source):
					var material := source.duplicate() as StandardMaterial3D
					material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					materials[source] = material
				mesh.set_surface_override_material(surface, materials[source])
	return model

func _pavement(parent: Node3D, name_: String, position_: Vector3, size: Vector2) -> Node3D:
	# Preserve the source tile's one-metre UV density on long sections.
	var model := _model(parent, URBAN_MODELS + "road-asphalt-pavement.glb", name_, position_, Vector3(size.x, 0.00001, size.y))
	model.position = position_
	model.scale = Vector3.ONE
	var surface := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-size.x * 0.5, 0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0, size.y * 0.5),
		Vector3(-size.x * 0.5, 0, size.y * 0.5),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(6, 12), Vector2(6 - size.x, 12),
		Vector2(6 - size.x, 12 - size.y), Vector2(6, 12 - size.y),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	# Godot treats clockwise triangles as front-facing (the imported tile uses this order).
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 3, 0])
	var tiled_mesh := ArrayMesh.new()
	tiled_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.mesh = tiled_mesh
	surface.add_to_group("weather_wet_surface", true)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model

func _box(parent: Node3D, name_: String, position_: Vector3, size: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name_
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = position_
	mesh.layers = 2
	_attach(parent, mesh)
	if solid:
		var body := StaticBody3D.new()
		body.name = name_ + "Body"
		body.position = position_
		_attach(parent, body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		_attach(body, collision)
	return mesh

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _label(parent: Node3D, text_: String, position_: Vector3, size_: int = 30) -> Label3D:
	var label := Label3D.new()
	label.text = text_
	label.position = position_
	label.font_size = size_
	label.pixel_size = 0.006
	label.layers = 2
	label.modulate = Color(1, 0.95, 0.8)
	_attach(parent, label)
	return label

func _light(parent: Node3D, position_: Vector3, energy: float, radius: float) -> void:
	var light: Light3D
	if radius > 10.0:
		var spot := SpotLight3D.new()
		spot.rotation.x = -PI * 0.5
		spot.spot_range = radius
		spot.spot_angle = 65.0
		spot.spot_attenuation = 0.6
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = radius
		omni.omni_attenuation = 0.7
		light = omni
	light.position = position_
	light.name = "Light"
	light.light_color = Color(1.0, 0.73, 0.39)
	light.light_energy = 0.0
	light.light_cull_mask = 2
	light.layers = 2
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	light.add_to_group("city_night_light", true)
	light.set_meta("night_energy", energy)
	_attach(parent, light)

func _bulb(parent: Node3D, position_: Vector3, size: Vector3) -> void:
	var material := _material(Color(0.85, 0.8, 0.64))
	material.emission_enabled = true
	material.emission_energy_multiplier = 0.0
	var mesh := _box(parent, "LampGlass", position_, size, material)
	mesh.set_meta("city_window_surface", 0)

func _tree(parent: Node3D, at: Vector3, pine: bool = false) -> void:
	var tree := StaticBody3D.new()
	tree.name = "Pine" if pine else "StreetTree"
	tree.position = at
	_attach(parent, tree)
	_model(tree, URBAN_MODELS + ("tree-park-pine-large.glb" if pine else "tree-park-large.glb"), "Model", Vector3.ZERO, Vector3(5, 8, 5) if pine else Vector3(4, 6.5, 4))
	var collision := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.28
	trunk.height = 2.8
	collision.shape = trunk
	collision.position.y = 1.4
	_attach(tree, collision)
	var canopy := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	canopy.shape = sphere
	canopy.position.y = 5.0
	_attach(tree, canopy)

func _build() -> void:
	city = Node3D.new()
	city.name = "FlashbackRoom"
	city.set_script(load("res://scripts/mini_city.gd"))
	city.set_meta("rain_bounds", Rect2(-62, -142, 124, 160))
	grass = _material(Color(0.27, 0.43, 0.25))
	white = _material(Color(0.92, 0.89, 0.75))
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1, 0.94, 0.79)
	sun.light_cull_mask = 2
	sun.layers = 2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	_attach(city, sun)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position = Vector3(0, -0.2, -62)
	_attach(city, ground)
	var ground_mesh := _box(ground, "Mesh", Vector3.ZERO, Vector3(128, 0.4, 164), grass)
	ground_mesh.add_to_group("weather_wet_surface", true)
	var ground_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(128, 0.4, 164)
	ground_shape.shape = shape
	_attach(ground, ground_shape)
	_container(city, "Clouds")
	var roads := _container(city, "Roads")
	_street(roads, "GardenStreet", "САДОВАЯ УЛИЦА", Vector3(-30, 0, -70), 82.0, false)
	_street(roads, "MapleStreet", "КЛЕНОВАЯ УЛИЦА", Vector3(30, 0, -70), 82.0, false)
	_street(roads, "SunStreet", "СОЛНЕЧНАЯ УЛИЦА", Vector3(0, 0, -24), 70.0, true)
	_street(roads, "RiverStreet", "РЕЧНАЯ УЛИЦА", Vector3(0, 0, -116), 70.0, true)
	var crossings := _container(city, "PedestrianCrossings")
	_crosswalk(crossings, "NorthCrossing", Vector3(0, 0, -24), true)
	_crosswalk(crossings, "SouthCrossing", Vector3(0, 0, -116), true)
	_crosswalk(crossings, "WestCrossing", Vector3(-30, 0, -70), false)
	_crosswalk(crossings, "EastCrossing", Vector3(30, 0, -70), false)
	var houses := _container(city, "Houses")
	for row in range(4):
		var x: float = [-46.0, -14.0, 14.0, 46.0][row]
		for lot in range(5):
			_house(houses, Vector3(x, 0, -38 - lot * 16), PI * 0.5 if row % 2 == 0 else -PI * 0.5, 7.6)
	for lot in range(5):
		var x: float = [-25.0, -14.0, -5.5, 13.0, 25.0][lot]
		_house(houses, Vector3(x, 0, -9), PI, 5.8 if lot == 2 else 7.0)
		_house(houses, Vector3(-24 + lot * 12, 0, -131), 0.0, 8.0)
	var trees := _container(city, "Trees")
	for z in [-40.0, -57.0, -74.0, -91.0, -108.0]:
		for x in [-38.0, -6.0, 6.0, 38.0]:
			_tree(trees, Vector3(x, 0, z + 5))
	for x in [-58.0, 58.0]:
		for index in range(10):
			_tree(trees, Vector3(x, 0, 8 - index * 16), true)
	var park := _container(city, "CentralGarden")
	_pavement(park, "GardenPath", Vector3(0, 0.04, -70), Vector2(3.2, 76))
	_pavement(city, "EntranceWalkway", Vector3(0, 0.04, -5), Vector2(3.2, 22))
	for z in [-49.0, -75.0, -97.0]:
		var bench := _model(park, URBAN_MODELS + "detail-bench.glb", "Bench", Vector3(3.6, 0, z), Vector3(2.0, 1.0, 0.8))
		# The model's seat faces -Z; turn it toward the garden path at X = 0.
		bench.rotation.y = PI * 0.5
	_entrance()
	_boundary()
	_traffic()
	var packed := PackedScene.new()
	var error := packed.pack(city)
	assert(error == OK)
	assert(ResourceSaver.save(packed, "res://scenes/flashback_room.tscn") == OK)
	print("BUILT: %d houses, 4 streets, 6 traffic vehicles" % house_count)
	city.free()
	quit()

func _street(parent: Node3D, name_: String, title: String, center: Vector3, length_: float, horizontal: bool) -> void:
	var street := _container(parent, name_)
	street.set_meta("street_name", title)
	var count := int(ceil(length_ / 8.0))
	var step := length_ / count
	for index in range(count):
		var offset := -length_ * 0.5 + (index + 0.5) * step
		var position_ := center + (Vector3(offset, 0.025, 0) if horizontal else Vector3(0, 0.025, offset))
		var tile := _model(street, URBAN_MODELS + "road-asphalt-center.glb", "RoadTile", position_, Vector3(step, 0.00001, 10) if horizontal else Vector3(10, 0.00001, step))
		for mesh in tile.find_children("*", "MeshInstance3D", true, false):
			mesh.add_to_group("weather_wet_surface", true)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var outside: bool = (side > 0.0) == (center.z > -70.0) if horizontal else (side > 0.0) == (center.x > 0.0)
		var sidewalk_length := (76.0 if outside else 50.0) if horizontal else (108.0 if outside else 82.0)
		var offset := Vector3(0, 0, side * 6.5) if horizontal else Vector3(side * 6.5, 0, 0)
		_pavement(street, "Sidewalk", center + offset + Vector3(0, 0.04, 0), Vector2(sidewalk_length, 3) if horizontal else Vector2(3, sidewalk_length))
		var lamp_count := 3 if horizontal else 5
		for index in range(lamp_count):
			var along := -sidewalk_length * 0.5 + 6.5 + index * (sidewalk_length - 13.0) / maxf(lamp_count - 1, 1)
			var at := center + offset + (Vector3(along, 0, 0) if horizontal else Vector3(0, 0, along))
			var lamp := _container(street, "StreetLamp_%s_%02d" % ["Left" if side < 0 else "Right", index + 1])
			lamp.position = at
			lamp.rotation.y = (PI if side < 0 else 0.0) if horizontal else side * PI * 0.5
			lamp.add_to_group("city_street_lamp", true)
			var lamp_body := StaticBody3D.new()
			_attach(lamp, lamp_body)
			var lamp_collision := CollisionShape3D.new()
			var pole := CylinderShape3D.new()
			pole.radius = 0.18
			pole.height = 5.1
			lamp_collision.shape = pole
			lamp_collision.position.y = 2.55
			_attach(lamp_body, lamp_collision)
			var model := _model(lamp, URBAN_MODELS + "detail-light-single.glb", "Model", Vector3.ZERO, Vector3(0.45, 5.2, 1.4))
			# Keep the original pole pivot; centering the asymmetrical arm offsets it.
			model.position = Vector3.ZERO
			model.scale = Vector3.ONE * model.scale.y
			var lens_position := LAMP_LENS_CENTER * model.scale
			_light(lamp, lens_position + Vector3.DOWN * 0.08, 8.0, 13.0)
			_bulb(lamp, lens_position, LAMP_LENS_SIZE * model.scale)
			if index == 0:
				var sign := _label(lamp, title, Vector3(0, 2.7, -0.18), 22)
				sign.rotation.y = PI
	for index in range(int(length_ / 6.0)):
		var along := -length_ * 0.5 + 3 + index * 6
		_box(street, "LaneMarking", center + Vector3(along if horizontal else 0, 0.05, 0 if horizontal else along), Vector3(2.5, 0.01, 0.12) if horizontal else Vector3(0.12, 0.01, 2.5), white)

func _crosswalk(parent: Node3D, name_: String, center: Vector3, horizontal_road: bool) -> void:
	var crossing := _container(parent, name_)
	crossing.position = center
	crossing.add_to_group("city_crosswalk", true)
	for index in range(8):
		var along := -4.375 + index * 1.25
		var offset := Vector3(0, 0.055, along) if horizontal_road else Vector3(along, 0.055, 0)
		var size := Vector3(3.2, 0.01, 0.6) if horizontal_road else Vector3(0.6, 0.01, 3.2)
		_box(crossing, "Stripe_%02d" % (index + 1), offset, size, white)

func _house(parent: Node3D, at: Vector3, yaw: float, width: float) -> void:
	var house := StaticBody3D.new()
	house_count += 1
	house.name = "House%02d" % house_count
	house.position = at
	house.rotation.y = yaw
	house.add_to_group("city_house", true)
	_attach(parent, house)
	var family := "b" if house_count % 3 == 0 else "a"
	var floors := 3 if house_count % 5 == 0 else (2 if house_count % 2 == 0 else 1)
	var depth := maxf(width * 0.82, 5.0)
	var roof: String = ["wall-a-roof", "wall-b-roof", "roof-metal-type-a", "wall-a-roof-slant"][house_count % 4]
	var model := _container(house, "Model")
	var sources := PackedStringArray([
		URBAN_MODELS + "wall-%s-window.glb" % family,
		URBAN_MODELS + "wall-%s-door.glb" % family,
		URBAN_MODELS + "window-wide-type-a.glb",
		URBAN_MODELS + roof + ".glb",
	])
	model.set_meta("source_model", sources[0])
	model.set_meta("source_models", sources)
	house.set_meta("floors", floors)
	var key := "%s:%s:%d:%.2f" % [family, roof, floors, width]
	if not house_meshes.has(key):
		var module_size := Vector3(width * 0.5, 3.4, depth * 0.5)
		for floor_index in range(floors):
			for row in range(2):
				for column in range(2):
					var door := floor_index == 0 and row == 1 and column == 0
					var file := "wall-%s-%s.glb" % [family, "door" if door else "window"]
					var position_ := Vector3((column - 0.5) * width * 0.5, floor_index * 3.4, (row - 0.5) * depth * 0.5)
					var module := _model(model, URBAN_MODELS + file, "WallModule", position_, module_size)
					module.rotation.y = PI if row == 1 else 0.0
			for side in [-1.0, 1.0]:
				for row in range(2):
					var at_window := Vector3(side * (width * 0.5 + 0.04), floor_index * 3.4 + 0.85, (row - 0.5) * depth * 0.5)
					var window := _model(model, sources[2], "SideWindow", at_window, Vector3(1.5, 1.6, 0.1))
					window.rotation.y = -side * PI * 0.5
	if not house_meshes.has(key):
		_model(model, sources[3], "Roof", Vector3(0, floors * 3.4, 0), Vector3(width + 0.35, 1.45, depth + 0.3))
		house_meshes[key] = _merge_modules(model)
	else:
		var mesh := MeshInstance3D.new()
		mesh.name = "Building"
		mesh.mesh = house_meshes[key]
		mesh.layers = 2
		_attach(model, mesh)
	var building := model.get_node("Building") as MeshInstance3D
	building.add_to_group("weather_wet_surface", true)
	for surface in range(building.mesh.get_surface_count()):
		var material := building.get_active_material(surface) as StandardMaterial3D
		if material != null and material.resource_name == "windows":
			var glass := material.duplicate() as StandardMaterial3D
			glass.emission_enabled = true
			glass.emission_energy_multiplier = 0.0
			building.set_surface_override_material(surface, glass)
			building.set_meta("city_window_surface", surface)
	if not shapes.has(building.mesh):
		shapes[building.mesh] = building.mesh.create_trimesh_shape()
	var collision := CollisionShape3D.new()
	collision.name = "BuildingCollision"
	collision.shape = shapes[building.mesh]
	_attach(house, collision)
	_label(house, str(house_count), Vector3(0, 2.5, depth * 0.5 + 0.06), 24)
	_light(house, Vector3(0, 1.8, depth * 0.5 + 0.5), 0.65, 3.2)
	var sidewalk_edge := 38.0 if absf(at.x) > 30.0 else 22.0
	var faces_vertical_street := absf(yaw) > PI * 0.25 and absf(yaw) < PI * 0.75
	var destination := Vector3(signf(at.x) * sidewalk_edge, 0, at.z) if faces_vertical_street else Vector3(at.x, 0, -16.0 if at.z > -70.0 else -124.0)
	var target_local: Vector3 = house.transform.affine_inverse() * destination
	var start_z := depth * 0.5 - 0.04
	var end_z := target_local.z + 0.08
	assert(end_z > start_z, "The house entrance does not face a sidewalk")
	_pavement(house, "EntrancePath", Vector3(-width * 0.25, 0.04, (start_z + end_z) * 0.5), Vector2(1.5, end_z - start_z))

func _merge_modules(model: Node3D) -> ArrayMesh:
	# Merge by material so a modular building remains inexpensive in Compatibility.
	var surfaces: Dictionary = {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(index) as StandardMaterial3D
			var key := material.resource_name
			if material.albedo_texture != null:
				key += "|" + material.albedo_texture.resource_path
			if not surfaces.has(key):
				var surface_tool := SurfaceTool.new()
				surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface_tool.set_material(material)
				surfaces[key] = surface_tool
			var output: SurfaceTool = surfaces[key]
			output.append_from(mesh.mesh, index, _relative(mesh, model))
	var merged := ArrayMesh.new()
	for tool: SurfaceTool in surfaces.values():
		tool.commit(merged)
	for module in model.get_children():
		module.free()
	var building := MeshInstance3D.new()
	building.name = "Building"
	building.mesh = merged
	building.layers = 2
	_attach(model, building)
	return merged

func _entrance() -> void:
	# This memory continues through the far house; there is no return portal.
	_box(city, "EntrancePath", Vector3(0, 0.015, -5), Vector3(4, 0.02, 32), _material(Color(0.65, 0.61, 0.5)))
	var arrival := Marker3D.new()
	arrival.name = "Arrival"
	arrival.position = Vector3(0, 0.92, 3)
	_attach(city, arrival)

func _boundary() -> void:
	var boundary := StaticBody3D.new()
	boundary.name = "Boundary"
	_attach(city, boundary)
	for item in [[Vector3(-64, 4, -62), Vector3(0.3, 8, 164)], [Vector3(64, 4, -62), Vector3(0.3, 8, 164)], [Vector3(0, 4, -144), Vector3(128, 8, 0.3)], [Vector3(0, 4, 20), Vector3(128, 8, 0.3)]]:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = item[1]
		collision.shape = shape
		collision.position = item[0]
		_attach(boundary, collision)

func _traffic() -> void:
	var traffic := _container(city, "Traffic")
	for lane in range(2):
		var path := Path3D.new()
		path.name = "InnerLane" if lane == 0 else "OuterLane"
		var margin := -1.8 if lane == 0 else 1.8
		var left := -30.0 - margin
		var right := 30.0 + margin
		var top := -116.0 - margin
		var bottom := -24.0 + margin
		var radius := 4.0
		var corners := [Vector2(right - radius, top + radius), Vector2(right - radius, bottom - radius), Vector2(left + radius, bottom - radius), Vector2(left + radius, top + radius)]
		var points: Array[Vector3] = []
		for corner in range(4):
			for step in range(9):
				var angle := -PI * 0.5 + corner * PI * 0.5 + step * PI / 16.0
				var point: Vector2 = corners[corner] + Vector2(cos(angle), sin(angle)) * radius
				points.append(Vector3(point.x, 0.065, point.y))
		if lane == 1:
			points.reverse()
		points.append(points[0])
		path.curve = Curve3D.new()
		path.curve.bake_interval = 0.25
		for point in points:
			path.curve.add_point(point)
		_attach(traffic, path)
		for index in range(3):
			var car := PathFollow3D.new()
			car.name = "Car%d" % index
			car.rotation_mode = PathFollow3D.ROTATION_Y
			car.loop = true
			car.set_script(load("res://scripts/city_traffic_car.gd"))
			car.set("cruise_speed", 4.5 + index * 0.4)
			_attach(path, car)
			car.progress = path.curve.get_baked_length() * (float(index) / 3.0 + lane * 0.08)
			var body := AnimatableBody3D.new()
			body.name = "Body"
			body.collision_layer = 2
			body.collision_mask = 3
			body.sync_to_physics = false
			_attach(car, body)
			var vehicle: String = ["truck-grey", "truck-green", "truck-flat"][index]
			var model := _model(body, URBAN_MODELS + vehicle + ".glb", "Model", Vector3.ZERO, Vector3(1.75, 1.95, 3.45))
			model.rotation.y = PI
			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.75, 1.9, 3.45)
			collision.shape = shape
			collision.position.y = 0.98
			_attach(body, collision)
			_light(body, Vector3(0, 0.65, -1.75), 0.8, 7.0)
			for x in [-0.57, 0.57]:
				_bulb(body, Vector3(x, 0.65, -1.74), Vector3(0.25, 0.15, 0.07))

