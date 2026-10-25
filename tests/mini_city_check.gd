extends SceneTree
## Integration checks use an in-memory save manager, preserving the player's save file.
class MemorySave extends "res://scripts/save_manager.gd":
	func restore_player(_player: CharacterBody3D) -> bool:
		return false
	func has_valid_checkpoint() -> bool:
		return false
	func save_player_checkpoint(player: CharacterBody3D, id: String, location_id: String = "", spawn_transform: Variant = null) -> void:
		if not location_id.is_empty():
			current_location_id = location_id
		checkpoint_id = id
		player.checkpoint_transform = player.global_transform if spawn_transform == null else spawn_transform

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	root.get_node("SaveManager").set_script(MemorySave)
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	var player = game.get_node("Player")
	var menu = game.get_node("MainMenu")
	menu.start_with_cutscene = false
	menu._start_game()
	player.set_physics_process(false)
	var city = game.get_node("FlashbackRoom")
	var weather = game.get_node("StreetWeather")
	var route = game.get_node("FlashbackTransition")
	var tools = game.get_node("DeveloperTools")
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	var laboratory_environment := camera.environment
	assert(city.get_node("Houses").get_child_count() == 30)
	assert(city.get_node("Roads").get_child_count() == 4)
	_check_sidewalks(city)
	_check_pedestrian_access(city)
	_check_benches(city)
	_check_street_lamps(city)
	assert(city.windows.size() >= 30 and city.lamps.size() >= 30)
	for lamp in city.lamps:
		assert((lamp.layers & 2) != 0 and lamp.light_cull_mask == 2, "City camera cannot see a street light")
	assert(not city.visible and not weather.in_street)
	assert(not weather.set_time_of_day(-1) and not weather.set_time_of_day(3))
	for house in city.get_node("Houses").get_children():
		assert(house.get_node("Model").has_meta("source_model"))
		for source in house.get_node("Model").get_meta("source_models"):
			assert(str(source).begins_with("res://assets/models/citymodels realism/"))
		var building := house.get_node("Model/Building") as MeshInstance3D
		assert(building.has_meta("city_window_surface"), "A house is missing its illuminated window material")
		assert(building.mesh.get_surface_count() < 10, "House materials were not merged")
		assert(house.get_node("BuildingCollision").shape is ConcavePolygonShape3D)
	route.fade_out_duration = 0.05
	route.black_hold_duration = 0.01
	route.fade_in_duration = 0.05
	route.blur_clear_duration = 0.05
	assert(route.request_transition(true))
	await create_timer(0.4).timeout
	player.set_physics_process(false)
	assert(route.in_city and weather.in_street and city.visible)
	assert(camera.environment == weather.environment)
	var cars: Array[PathFollow3D] = []
	for path in city.get_node("Traffic").get_children():
		for car in path.get_children():
			cars.append(car)
	assert(cars.size() == 6)
	var progress_before: Array[float] = []
	for car in cars:
		progress_before.append(car.progress)
	await create_timer(1.3).timeout
	for index in range(cars.size()):
		assert(cars[index].progress > progress_before[index] + 0.1, "Traffic vehicle did not move")
	var blocker := StaticBody3D.new()
	var obstruction := CollisionShape3D.new()
	var obstacle_shape := BoxShape3D.new()
	obstacle_shape.size = Vector3(2.2, 2.0, 1.0)
	obstruction.shape = obstacle_shape
	blocker.add_child(obstruction)
	game.add_child(blocker)
	blocker.global_position = cars[0].global_position - cars[0].global_basis.z * 4.0 + Vector3.UP
	await create_timer(0.7).timeout
	assert(cars[0].speed < 0.01, "Vehicle did not brake for a physical obstacle")
	blocker.queue_free()
	await create_timer(0.8).timeout
	assert(cars[0].speed > 0.5, "Traffic did not resume after removing the obstacle")
	var panel = city.get_node("StreetWeatherPanel")
	assert(panel.buttons.size() == 7)
	panel.players_in_zone[player.get_instance_id()] = weakref(player)
	assert(panel.activate(6, player) and weather.time_of_day == 2)
	tools.toggle()
	assert(tools.opened and tools.time_picker.item_count == 3)
	assert(tools.time_picker.selected == 2)
	await create_timer(1.7).timeout
	assert(city.lighting_strength > 0.99)
	assert(city.windows[0].emission_energy_multiplier > 2.0)
	assert(city.lamps[0].light_energy > 0.5 and city.lamps[0].visible)
	var progress_at_pause: float = cars[0].progress
	paused = true
	await create_timer(0.25, true).timeout
	assert(is_equal_approx(cars[0].progress, progress_at_pause), "Traffic continued during pause")
	paused = false
	tools._on_time_selected(0)
	await create_timer(1.7).timeout
	assert(weather.time_of_day == 0 and city.lighting_strength < 0.01)
	assert(city.lamps[0].light_energy < 0.01 and not city.lamps[0].visible)
	assert(is_zero_approx(weather.environment.fog_height_density))
	tools._on_weather_selected(3)
	await create_timer(1.7).timeout
	assert(weather.mode == 3 and weather.time_of_day == 0)
	assert(weather.environment.fog_enabled)
	assert(is_equal_approx(weather.environment.fog_density, weather.PRESETS[3].fog_density))
	assert(is_equal_approx(weather.environment.fog_height_density, weather.PRESETS[3].fog_height_density))
	assert(city.lighting_strength > 0.99 and weather.rain.emitting and weather.rain_sound.playing)
	assert(weather.wet_materials[0].get_shader_parameter("wetness") > 0.99)
	assert(weather.rain_points.size() > 1000)
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	for index in range(0, weather.rain_points.size(), 37):
		var point: Vector3 = city.to_global(weather.rain_points[index])
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 25.0, 1))
		assert(not hit.is_empty(), "Rain starts outside the city ground")
		var collider: Node = hit.collider
		var hit_lamp := collider.get_parent() != null and collider.get_parent().is_in_group("city_street_lamp")
		assert(collider == city.get_node("Ground") or hit_lamp, "Rain starts above a roof")
	tools.close()
	assert(route.request_transition(false))
	await create_timer(0.4).timeout
	player.set_physics_process(false)
	assert(not weather.in_street and not city.visible)
	assert(weather.mode == 0 and weather.time_of_day == 0)
	assert(camera.environment == laboratory_environment)
	assert(is_zero_approx(weather.environment.fog_height_density))
	assert(not weather.rain.emitting and not weather.rain_sound.playing and not weather.thunder_sound.playing)
	var stopped_progress: float = cars[0].progress
	await create_timer(0.25).timeout
	assert(is_equal_approx(cars[0].progress, stopped_progress))
	print("PASS: 30 houses and entrance paths, 4 streets and crossings, 6 moving cars, weather, lighting and laboratory isolation")
	if OS.get_cmdline_user_args().has("--visual-city") or OS.get_cmdline_user_args().has("--visual-benches"):
		assert(route.request_transition(true))
		await create_timer(0.4).timeout
		player.set_physics_process(false)
		if OS.get_cmdline_user_args().has("--visual-benches"):
			await _preview_benches(game, city, weather)
		else:
			await _preview(game, city, weather)
	quit()

func _check_street_lamps(city: Node3D) -> void:
	var lamp_count := 0
	for street in city.get_node("Roads").get_children():
		var road_center := Vector3.ZERO
		var tiles := 0
		for child in street.get_children():
			if str(child.get_meta("source_model", "")).ends_with("road-asphalt-center.glb"):
				road_center += child.global_position
				tiles += 1
		assert(tiles > 0)
		road_center /= tiles
		for lamp in street.get_children():
			if not lamp.is_in_group("city_street_lamp"):
				continue
			lamp_count += 1
			var model := lamp.get_node("Model") as Node3D
			var glass := lamp.get_node("LampGlass") as MeshInstance3D
			var light := lamp.get_node("Light") as SpotLight3D
			assert(model.global_position.is_equal_approx(lamp.global_position), "Pole is offset from its base")
			assert(glass.global_basis.y.normalized().dot(Vector3.UP) > 0.999, "Lens is tilted")
			assert((-light.global_basis.z).dot(Vector3.DOWN) > 0.999, "Lamp does not point down")
			var toward_road: Vector3 = road_center - lamp.global_position
			toward_road.z = 0.0 if street.name in ["GardenStreet", "MapleStreet"] else toward_road.z
			toward_road.x = 0.0 if street.name in ["SunStreet", "RiverStreet"] else toward_road.x
			toward_road.y = 0.0
			assert((-lamp.global_basis.z).dot(toward_road.normalized()) > 0.999, "Lamp arm faces away from the road")
			var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var faces := mesh.mesh.get_faces()
			var size: Vector3 = (glass.mesh as BoxMesh).size
			for x in [-0.5, 0.5]:
				for z in [-0.5, 0.5]:
					var point: Vector3 = glass.global_transform * (Vector3(x, 0.5, z) * size)
					var source := mesh.global_transform.affine_inverse() * point
					var up := (mesh.global_basis.inverse() * Vector3.UP).normalized()
					var gap := INF
					for index in range(0, faces.size(), 3):
						var hit: Variant = Geometry3D.ray_intersects_triangle(source, up, faces[index], faces[index + 1], faces[index + 2])
						if hit is Vector3:
							gap = minf(gap, point.distance_to(mesh.global_transform * hit))
					assert(gap < 0.03, "Lens extends beyond the actual model's lamp head")
	assert(lamp_count == 32)

func _check_sidewalks(city: Node3D) -> void:
	var expected := {
		"GardenStreet": { -36.5: Vector2(3, 108), -23.5: Vector2(3, 82) },
		"MapleStreet": { 23.5: Vector2(3, 82), 36.5: Vector2(3, 108) },
		"SunStreet": { -30.5: Vector2(50, 3), -17.5: Vector2(76, 3) },
		"RiverStreet": { -122.5: Vector2(76, 3), -109.5: Vector2(50, 3) },
	}
	var road_rects: Array[Rect2] = []
	for street in city.get_node("Roads").get_children():
		for child in street.get_children():
			if str(child.get_meta("source_model", "")).ends_with("road-asphalt-center.glb"):
				var tile := child.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				var size: Vector3 = child.scale * tile.get_aabb().size
				road_rects.append(Rect2(Vector2(child.position.x, child.position.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	var count := 0
	for street in city.get_node("Roads").get_children():
		var found := {}
		for child in street.get_children():
			if not str(child.get_meta("source_model", "")).ends_with("road-asphalt-pavement.glb"):
				continue
			count += 1
			var mesh := child.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var size3 := mesh.get_aabb().size
			var size := Vector2(size3.x, size3.z)
			var position: Vector3 = child.position
			var coordinate: float = position.z if street.name in ["SunStreet", "RiverStreet"] else position.x
			assert(expected[street.name].has(coordinate), "Sidewalk is misplaced")
			assert(size.is_equal_approx(expected[street.name][coordinate]), "Sidewalk has an incorrect length")
			assert(is_equal_approx(position.y, 0.04), "Sidewalk has an incorrect height")
			assert(mesh.get_active_material(0) != null and mesh.is_in_group("weather_wet_surface"))
			var uv: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			assert(is_equal_approx(absf(uv[0].x - uv[1].x), size.x), "Pavement texture is stretched along X")
			assert(is_equal_approx(absf(uv[0].y - uv[3].y), size.y), "Pavement texture is stretched along Z")
			var faces := mesh.mesh.get_faces()
			assert(faces.size() == 6 and (faces[1] - faces[0]).cross(faces[2] - faces[0]).y < 0.0, "Sidewalk faces are culled from above")
			var rect := Rect2(Vector2(position.x, position.z) - size * 0.5, size)
			for road in road_rects:
				var overlap := rect.intersection(road)
				assert(overlap.size.x * overlap.size.y < 0.001, "Sidewalk covers a vehicle lane")
			found[coordinate] = true
		assert(found.size() == 2, "A street is missing a sidewalk")
	assert(count == 8)
	var garden := city.get_node("CentralGarden/GardenPath") as Node3D
	var entrance := city.get_node("EntranceWalkway") as Node3D
	assert(is_equal_approx(garden.position.z, -70.0) and is_equal_approx(garden.get_child(0).get_aabb().size.z, 76.0))
	assert(is_equal_approx(entrance.position.z, -5.0) and is_equal_approx(entrance.get_child(0).get_aabb().size.z, 22.0))

func _check_pedestrian_access(city: Node3D) -> void:
	var sidewalks: Array[Rect2] = []
	for street in city.get_node("Roads").get_children():
		for child in street.get_children():
			if not str(child.get_meta("source_model", "")).ends_with("road-asphalt-pavement.glb"):
				continue
			var mesh := child.get_child(0) as MeshInstance3D
			var size := Vector2(mesh.get_aabb().size.x, mesh.get_aabb().size.z)
			sidewalks.append(Rect2(Vector2(child.position.x, child.position.z) - size * 0.5, size))
	assert(sidewalks.size() == 8)
	var paths := 0
	for house in city.get_node("Houses").get_children():
		var path := house.get_node("EntrancePath") as Node3D
		var mesh := path.get_child(0) as MeshInstance3D
		var length_: float = mesh.get_aabb().size.z
		var building := house.get_node("Model/Building") as MeshInstance3D
		var near_end: float = path.position.z - length_ * 0.5
		assert(absf(near_end - building.get_aabb().end.z) < 0.35, "Walkway does not begin at the building entrance")
		var far_end: Vector3 = house.transform * (path.position + Vector3(0, 0, length_ * 0.5))
		var joined := false
		for sidewalk in sidewalks:
			if sidewalk.grow(0.01).has_point(Vector2(far_end.x, far_end.z)):
				joined = true
				break
		assert(joined, "A house walkway does not reach a sidewalk")
		assert(mesh.get_active_material(0) != null and mesh.is_in_group("weather_wet_surface"))
		paths += 1
	assert(paths == 30)
	var crossings := city.get_node("PedestrianCrossings")
	var expected := {
		"NorthCrossing": Vector3(0, 0, -24),
		"SouthCrossing": Vector3(0, 0, -116),
		"WestCrossing": Vector3(-30, 0, -70),
		"EastCrossing": Vector3(30, 0, -70),
	}
	assert(crossings.get_child_count() == 4)
	for crossing in crossings.get_children():
		assert(crossing.is_in_group("city_crosswalk") and crossing.position.is_equal_approx(expected[crossing.name]))
		assert(crossing.get_child_count() == 8)
		for index in range(8):
			var stripe := crossing.get_child(index) as MeshInstance3D
			var horizontal: bool = crossing.name in ["NorthCrossing", "SouthCrossing"]
			var along: float = stripe.position.z if horizontal else stripe.position.x
			assert(is_equal_approx(along, -4.375 + index * 1.25))
			assert(is_equal_approx(stripe.position.y, 0.055))

func _check_benches(city: Node3D) -> void:
	var benches := 0
	for child in city.get_node("CentralGarden").get_children():
		if not str(child.get_meta("source_model", "")).ends_with("detail-bench.glb"):
			continue
		benches += 1
		var bench := child as Node3D
		var toward_path := Vector3(-bench.position.x, 0, 0).normalized()
		assert((-bench.basis.z).dot(toward_path) > 0.999, "A bench faces away from the walkway")
	assert(benches == 3)

func _preview(game: Node, city: Node3D, weather: Node) -> void:
	root.always_on_top = true
	root.size = Vector2i(1280, 800)
	DisplayServer.window_move_to_foreground()
	var tools = game.get_node("DeveloperTools")
	tools.process_mode = Node.PROCESS_MODE_DISABLED
	tools.launcher.hide()
	game.get_node("Tutorial").hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.far = 450.0
	camera.fov = 65.0
	camera.cull_mask = 2
	camera.environment = weather.environment
	camera.make_current()
	var overlay := CanvasLayer.new()
	game.add_child(overlay)
	var caption := Label.new()
	caption.position = Vector2(20, 20)
	caption.add_theme_font_size_override("font_size", 25)
	overlay.add_child(caption)
	for state in range(4):
		weather.call("set_weather", 3 if state == 3 else 0)
		weather.call("set_time_of_day", 2 if state == 2 else 0)
		if state == 0:
			camera.global_position = city.to_global(Vector3(93, 100, 42))
			camera.look_at(city.to_global(Vector3(0, 0, -66)))
		else:
			camera.global_position = city.to_global(Vector3(31, 2.4, -32))
			camera.look_at(city.to_global(Vector3(28, 2.4, -90)))
		caption.text = ["ГОРОД · 30 ДОМОВ / 4 УЛИЦЫ", "ГОРОД · ДНЕВНАЯ УЛИЦА", "ГОРОД · НОЧЬ · ФОНАРИ И ОКНА", "ГОРОД · ГРОЗА · ДОЖДЬ И ОСВЕЩЕНИЕ"][state]
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png("res://.godot/mini-city-%d.png" % state)
		assert(error == OK)
		await create_timer(4.0).timeout

func _preview_benches(game: Node, city: Node3D, weather: Node) -> void:
	root.always_on_top = true
	root.size = Vector2i(1280, 800)
	root.title = "Скамейки городского сквера"
	DisplayServer.window_move_to_foreground()
	var tools = game.get_node("DeveloperTools")
	tools.process_mode = Node.PROCESS_MODE_DISABLED
	tools.launcher.hide()
	game.get_node("Tutorial").hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.fov = 65.0
	camera.cull_mask = 2
	camera.environment = weather.environment
	camera.global_position = city.to_global(Vector3(0.2, 1.65, -78))
	camera.look_at(city.to_global(Vector3(3.6, 0.55, -75)))
	camera.make_current()
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://.godot/benches.png") == OK)
	await create_timer(2.0).timeout

