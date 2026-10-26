extends SceneTree
## Integration check with an in-memory checkpoint; does not write the player's save.

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
	var menu = game.get_node("MainMenu")
	menu.start_with_cutscene = false
	menu._start_game()
	var player = game.get_node("Player")
	player.set_physics_process(false)
	var city = game.get_node("FlashbackRoom")
	var city_route = game.get_node("FlashbackTransition")
	var weather = game.get_node("StreetWeather")
	var forest = game.get_node("ForestRoom") as Node3D
	var forest_route = game.get_node("ForestTransition")
	var developer_tools = game.get_node("DeveloperTools")
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var laboratory_environment := camera.environment
	assert(not forest.visible and not forest.get_node("ForestSun").visible)
	assert(not city.visible and not weather.in_street)
	developer_tools.refresh()
	assert(developer_tools.locations.any(func(location: Dictionary) -> bool: return location.location_id == "forest"), "Forest is missing from developer tools")
	var lab_access: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4.2, 1.5, 4), Vector3(7.1, 1.5, 4), 1))
	assert(lab_access.is_empty(), "A collision blocks the forest memory door")
	var trees := forest.get_node("Trees")
	var tree_count: int = forest.get_meta("tree_count")
	assert(tree_count >= 750)
	assert(trees.get_child_count() == tree_count + 2)
	for visual in trees.get_children():
		if visual is MultiMeshInstance3D:
			assert(str(visual.get_meta("source_model", "")).begins_with("res://assets/models/citymodels realism/"))
			assert(not str(visual.get_meta("source_model", "")).contains("park"), "Park planters were placed in the forest")
			assert(visual.multimesh.buffer.size() == visual.multimesh.instance_count * 12, "Tree instances were not serialized")
			assert(visual.multimesh.custom_aabb.size.length() > 100.0, "Tree instances will be culled")
	var path := forest.get_node("WindingTrail")
	var controls: Array = path.get_meta("centerline")
	var west := INF
	var east := -INF
	for point in controls:
		west = minf(west, point.x)
		east = maxf(east, point.x)
	assert(west < -13.0 and east > 13.0 and path.get_meta("length") > 210.0)
	for mesh in [path.get_node("LeafyEdges"), path.get_node("DirtPath")]:
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		assert(faces.size() > 100 and (faces[1] - faces[0]).cross(faces[2] - faces[0]).y < 0, "The forest trail is hidden from above")
	assert(game.get_node("Room/ForestMemoryDoor").global_position.distance_to(forest_route.get_node("LaboratoryExit").global_position) < 2.0)
	var good_memory_trigger := forest_route.get_node("LaboratoryExit") as Area3D
	assert(good_memory_trigger.transition_style == 1)
	assert(good_memory_trigger.flashback_title == "Хорошее воспоминание — лес")
	assert(game.get_node("Room/ForestMemorySign").text == "ХОРОШЕЕ ВОСПОМИНАНИЕ")
	assert(forest.get_node_or_null("ReturnArea") == null)
	assert(forest.get_node_or_null("ReturnGate") == null)
	assert(forest.find_child("ReturnLabel", true, false) == null)
	var arrival_position: Vector3 = forest.get_node("Arrival").position
	assert(arrival_position.z < -25.0 and arrival_position.z > -70.0, "Forest arrival is too close to the map edge")
	var closest_trail_point := INF
	for point in controls:
		closest_trail_point = minf(closest_trail_point, Vector2(arrival_position.x, arrival_position.z).distance_to(Vector2(point.x, point.z)))
	assert(closest_trail_point < 13.0, "Forest arrival is away from the path")
	for route in [city_route, forest_route]:
		route.fade_out_duration = 0.05
		route.black_hold_duration = 0.01
		route.fade_in_duration = 0.05
		route.blur_clear_duration = 0.05
	assert(not forest_route.request_transition(false))
	player.global_position = Vector3(good_memory_trigger.global_position.x, 0.92, good_memory_trigger.global_position.z)
	await physics_frame
	await physics_frame
	await create_timer(0.1).timeout
	assert(forest_route.transitioning, "The good-memory trigger did not start the flashback")
	assert(forest_route.fade_material.get_shader_parameter("light_tint") == good_memory_trigger.light_tint)
	assert(forest_route.transition_sound.stream == forest_route.TRANSITION_STREAM)
	await create_timer(0.35).timeout
	player.set_physics_process(false)
	assert(forest_route.in_city and not city_route.in_city and forest_route.transition_style == 1)
	assert(forest.visible and forest.get_node("ForestSun").visible)
	assert(not city.visible and not weather.in_street)
	assert(not weather.rain.emitting and not weather.rain_sound.playing)
	assert(camera.environment == forest_route.destination_environment)
	assert(root.get_node("SaveManager").current_location_id == "forest")
	developer_tools.refresh()
	assert(developer_tools.locations.any(func(location: Dictionary) -> bool: return location.location_id == "forest"))
	assert(player.global_position.distance_to(forest.get_node("Arrival").global_position) < 0.1)
	await physics_frame
	assert(forest_route.in_city and root.get_node("SaveManager").current_location_id == "forest", "Forest entry triggered an automatic return")
	assert(forest_route.request_transition(false))
	await create_timer(0.35).timeout
	player.set_physics_process(false)
	assert(not forest.visible and not forest.get_node("ForestSun").visible)
	assert(not city.visible and not city_route.in_city and not weather.in_street)
	assert(camera.environment == laboratory_environment)
	assert(root.get_node("SaveManager").current_location_id == "laboratory")
	assert(city_route.request_transition(true))
	await create_timer(0.35).timeout
	player.set_physics_process(false)
	assert(city.visible and weather.in_street and not forest.visible)
	assert(city_route.request_transition(false))
	await create_timer(0.35).timeout
	assert(not forest.visible and not city.visible)
	assert(not weather.in_street and camera.environment == laboratory_environment)
	# Continue restores checkpoint data after scene nodes have already run _ready().
	root.get_node("SaveManager").current_location_id = "forest"
	player.global_transform = forest.get_node("Arrival").global_transform
	root.get_node("SaveManager").checkpoint_restored.emit("forest")
	assert(forest_route.in_city and forest.visible and camera.environment == forest_route.destination_environment)
	assert(not city.visible and not weather.in_street)
	root.get_node("SaveManager").current_location_id = "laboratory"
	player.global_transform = forest_route.get_node("LaboratoryArrival").global_transform
	root.get_node("SaveManager").checkpoint_restored.emit("laboratory")
	assert(not forest_route.in_city and not forest.visible and camera.environment == laboratory_environment)
	root.get_node("SaveManager").current_location_id = "flashback"
	player.global_transform = city.get_node("Arrival").global_transform
	root.get_node("SaveManager").checkpoint_restored.emit("flashback")
	assert(city_route.in_city and city.visible and weather.in_street)
	assert(not forest.visible and camera.environment == weather.environment)
	root.get_node("SaveManager").current_location_id = "laboratory"
	player.global_transform = forest_route.get_node("LaboratoryArrival").global_transform
	root.get_node("SaveManager").checkpoint_restored.emit("laboratory")
	assert(not city.visible and not forest.visible and camera.environment == laboratory_environment)
	print("PASS: good-memory trigger, warm forest flashback, no return teleporter and city isolation")
	if OS.get_cmdline_user_args().has("--visual-forest"):
		assert(forest_route.request_transition(true))
		await create_timer(0.35).timeout
		await _preview_forest(game, forest, forest_route)
	quit()

func _preview_forest(game: Node, forest: Node3D, route: Node) -> void:
	root.always_on_top = true
	root.size = Vector2i(1280, 800)
	root.title = "Густой лес — извилистая тропа"
	DisplayServer.window_move_to_foreground()
	var tools = game.get_node("DeveloperTools")
	tools.process_mode = Node.PROCESS_MODE_DISABLED
	tools.launcher.hide()
	game.get_node("Tutorial").hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.far = 260.0
	camera.fov = 70.0
	camera.make_current()
	camera.cull_mask = 1
	camera.environment = route.laboratory_environment
	camera.global_position = Vector3(3.8, 1.7, 4)
	camera.look_at(Vector3(7.7, 1.7, 4))
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://.godot/forest-lab-door.png") == OK)
	camera.cull_mask = 4
	camera.environment = route.destination_environment
	for index in range(3):
		var origin: Vector3 = [Vector3(0, 2.1, -6), Vector3(-13, 2.1, -45), Vector3(14, 2.1, -87)][index]
		var target: Vector3 = [Vector3(-8, 1.6, -34), Vector3(3, 1.6, -69), Vector3(-7, 1.6, -113)][index]
		camera.global_position = forest.to_global(origin)
		camera.look_at(forest.to_global(target))
		await create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://.godot/forest-%d.png" % index) == OK)
		await create_timer(1.0).timeout
