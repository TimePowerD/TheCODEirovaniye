extends SceneTree
## Exercise the real areas and checkpoint notifications without changing a user save.

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
		player.checkpoint_camera_rotation = player.camera_pivot.rotation
	func save_current_world_state() -> void:
		pass

var game: Node3D
var player: CharacterBody3D
var city: Node3D
var light_path: Node3D

func _initialize() -> void:
	create_timer(55.0).timeout.connect(func() -> void:
		push_error("Memory-city journey test timed out")
		quit(1)
	)
	call_deferred("_check")

func _sync() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _wait_until(predicate: Callable, seconds: float, message: String) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			push_error(message)
			quit(1)
			return
		await create_timer(0.025).timeout

func _check() -> void:
	var save := root.get_node("SaveManager")
	save.set_script(MemorySave)
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	game = current_scene as Node3D
	var menu = game.get_node("MainMenu")
	menu.start_with_cutscene = false
	menu._start_game()
	player = game.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	city = game.get_node("FlashbackRoom") as Node3D
	light_path = city.get_node("MemoryLightPath") as Node3D
	var journey = game.get_node("MemoryCityJourney")
	var entrance = game.get_node("LabModuleLibrary/Walls/CityMemoryTrigger")
	var door = city.get_node("FinalHouseDoor")
	var weather = game.get_node("StreetWeather")
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var lab_environment := camera.environment
	assert(entrance.destination_location_id == "flashback")
	assert(door.destination_location_id == "kitchen")
	assert(city.get_node_or_null("ReturnArea") == null and city.get_node_or_null("ReturnGate") == null)
	assert(not journey.active and not light_path.active and not weather.in_street)
	assert(light_path.segments.size() > 30)
	for trigger in [entrance, door]:
		trigger.fade_out_duration = 0.06
		trigger.hold_duration = 0.01
		trigger.fade_in_duration = 0.06
		trigger.blur_clear_duration = 0.06
	await _sync()
	# Pause leaves the actual entrance occupied, then the swap lock also holds it.
	paused = true
	player.global_position = entrance.global_position
	await create_timer(0.15).timeout
	assert(not entrance.transitioning and save.current_location_id == "laboratory")
	player.swap_in_progress = true
	paused = false
	await _sync()
	await create_timer(0.1).timeout
	assert(not entrance.transitioning and save.current_location_id == "laboratory")
	player.swap_in_progress = false
	await _wait_until(func() -> bool: return entrance.transitioning, 2.0, "Ventilation area did not begin a transition")
	await _wait_until(func() -> bool: return not entrance.transitioning, 3.0, "Ventilation flashback did not finish")
	assert(save.current_location_id == "flashback", "Ventilation skipped the city and sent the player to the kitchen")
	assert(player.global_position.distance_to(city.get_node("Arrival").global_position) < 0.1)
	assert(not door.kate_cutscene_played)
	assert(city.visible and journey.active and light_path.active and weather.in_street)
	assert(weather.mode == weather.Weather.STORM and weather.story_storm_active)
	assert(is_equal_approx(weather.rain_strength, 1.0) and weather.rain.emitting)
	assert(weather.rain_sound.playing and camera.environment == weather.environment)
	assert(weather.environment.fog_enabled and weather.environment.fog_density >= 0.09)
	assert(weather.artificial_light_strength > 0.0 and weather.artificial_light_strength < 0.5)
	assert(not weather.set_weather(weather.Weather.SUNNY) and not weather.set_time_of_day(weather.TimeOfDay.NIGHT))
	assert(weather.mode == weather.Weather.STORM)
	assert(camera.environment != lab_environment)
	assert(_check_walkable_path(), "The complete guided route must fit a standing player")
	assert(await _check_fading_lights(), "Guide light interaction checks failed")
	if OS.get_cmdline_user_args().has("--visual-memory-city"):
		await _preview_city(camera)
	# Restarting at the city checkpoint restores the route and its weather.
	player.return_to_checkpoint()
	await _sync()
	assert(player.global_position.distance_to(city.get_node("Arrival").global_position) < 0.1)
	for segment in light_path.segments:
		assert(not segment.consumed and segment.root.visible)
	assert(weather.story_storm_active and weather.rain.emitting)
	# Real approach to the house's entrance, before the facade's solid collider.
	player.global_position = city.to_global(Vector3(-2, 0.92, -125.8))
	await _sync()
	assert(not door.transitioning)
	player.global_position = city.to_global(Vector3(-2, 0.92, -126.9))
	await _wait_until(func() -> bool: return door.kate_cutscene_played, 3.0, "House door did not begin Kate's final cutscene")
	assert(save.current_location_id == "kitchen")
	assert(player.global_position.distance_to(game.get_node("KitchenRoom/Arrival").global_position) < 0.1)
	assert(not city.visible and not weather.in_street and not journey.active and not light_path.active)
	assert(not weather.rain.emitting and not weather.rain_sound.playing and not weather.thunder_sound.playing)
	assert(weather.thunder_remaining < 0.0 and weather.flash_light.light_energy == 0.0)
	assert(camera.environment != weather.environment)
	assert(player.has_meta("cutscene_active") and door.cutscene_storm_active)
	assert(game.get_node("KitchenRoom/Kate").visible)
	await _wait_until(func() -> bool: return not door.transitioning, 15.0, "Final kitchen cutscene did not complete")
	assert(not player.has_meta("cutscene_active") and not player.has_meta("location_transition_active"))
	assert(not game.get_node("KitchenRoom/Kate").visible)
	await _wait_until(func() -> bool: return game.get_node_or_null("EndCredits") != null, 6.0, "Final credits did not appear")
	print("PASS: ventilation -> storm/fog city, walkable fading trail, checkpoint reset, house -> final cutscene/credits, no laboratory return")
	quit()

func _check_walkable_path() -> bool:
	# A standing player capsule must fit all along the guided walk, not just at lamps.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var excluded: Array[RID] = [player.get_rid()]
	for body in city.get_node("Traffic").find_children("*", "PhysicsBody3D", true, false):
		excluded.append(body.get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = excluded
	var space := city.get_world_3d().direct_space_state
	var previous: Vector3 = city.get_node("Arrival").position
	for segment in light_path.segments:
		var point: Vector3 = segment.root.position
		var samples := maxi(1, int(ceil(previous.distance_to(point) / 0.5)))
		for index in range(1, samples + 1):
			var at := previous.lerp(point, float(index) / samples)
			at.y = 1.0
			query.transform = Transform3D(Basis.IDENTITY, city.to_global(at))
			var hits := space.intersect_shape(query)
			var blockers: Array[String] = []
			for hit in hits:
				blockers.append(str(hit.collider.get_path()))
			if not hits.is_empty():
				push_error("Guided path blocked at %s by %s" % [at, blockers])
				return false
		previous = point
	return true

func _check_fading_lights() -> bool:
	var segment: Dictionary = light_path.segments[4]
	var other := CharacterBody3D.new()
	other.collision_layer = 1
	other.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	other.add_child(collision)
	game.add_child(other)
	var position_: Vector3 = segment.root.global_position + Vector3.UP * 0.92
	other.global_position = position_
	await _sync()
	assert(not segment.consumed, "A non-player object consumed a guide light")
	other.queue_free()
	player.set_meta("location_transition_active", true)
	player.global_position = position_
	await _sync()
	assert(not segment.consumed, "A light disappeared while player controls were locked")
	player.remove_meta("location_transition_active")
	paused = true
	await create_timer(0.12).timeout
	assert(not segment.consumed)
	paused = false
	await _wait_until(func() -> bool: return bool(segment.consumed), 1.0, "Walking into a light did not consume it")
	await create_timer(light_path.fade_duration * 0.4).timeout
	var partial: float = segment.material.get_shader_parameter("amount")
	assert(partial > 0.0 and partial < 1.0, "Guide light did not fade gradually")
	await create_timer(light_path.fade_duration + 0.05).timeout
	assert(not segment.root.visible and is_zero_approx(segment.light.light_energy))
	player.global_transform = city.get_node("Arrival").global_transform
	await _sync()
	assert(segment.consumed and not segment.root.visible)
	light_path.set_active(false)
	light_path.set_active(true)
	assert(segment.consumed and not segment.root.visible, "Reactivating the route revived a consumed light")
	return true

func _preview_city(camera: Camera3D) -> void:
	root.always_on_top = true
	root.size = Vector2i(1280, 800)
	root.title = "SUBJECTIVE — дождливый город воспоминаний"
	DisplayServer.window_move_to_foreground()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tutorial := game.get_node("Tutorial")
	tutorial.hide()
	tutorial.set_process(false)
	var shots := [Vector3(0, 0.92, 3), Vector3(0, 0.92, -63), Vector3(-2, 0.92, -123)]
	for index in range(shots.size()):
		player.global_position = city.to_global(shots[index])
		player.rotation = Vector3.ZERO
		player.get_node("CameraPivot").rotation = Vector3(-0.12, 0, 0)
		await create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://.godot/memory-city-%d.png" % index) == OK)
	# Show one extinguishing patch on approach as well as the distant destination.
	var segment: Dictionary = light_path.segments[5]
	player.global_position = segment.root.global_position + Vector3(0, 0.92, 0.7)
	await create_timer(1.2).timeout
	assert(segment.consumed)
	assert(camera.environment == game.get_node("StreetWeather").environment)
