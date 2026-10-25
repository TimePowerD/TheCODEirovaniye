extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var game := current_scene
	var menu = game.get_node("MainMenu")
	menu._start_game()
	await physics_frame
	await physics_frame
	await process_frame
	var weather = game.get_node("StreetWeather")
	var player = game.get_node("Player")
	var route = game.get_node("FlashbackTransition")
	assert(game.get_node_or_null("LaboratoryWeatherPanel") == null, "Weather console is still in the laboratory")
	var street_panel = game.get_node("FlashbackRoom/StreetWeatherPanel")
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	var original_environment := camera.environment
	var original_camera_transform := camera.transform
	var original_lab_energy: float = game.get_node("OmniLight3D").light_energy
	assert(weather.mode == 0 and not weather.in_street)
	assert(not weather.street.visible and not weather.sun.is_visible_in_tree())
	assert(not weather.flash_light.is_visible_in_tree() and not street_panel.is_visible_in_tree())
	assert(not weather.set_weather(-1) and not weather.set_weather(4))
	assert(weather.rain != null and weather.rain_points.size() > 500)
	assert(not weather.rain.emitting and not weather.rain_sound.playing)
	# Every rain trajectory stays outside house/tree/gate roofs.
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for point in weather.rain_points:
		var world_point: Vector3 = weather.street.to_global(point)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(world_point, world_point - Vector3(0, 21, 0), 1))
		assert(not hit.is_empty() and hit.collider == weather.street.get_node("Ground"), "Rain passes through scenery")
	assert(not street_panel.activate(1), "Weather console works outside the street")
	route.fade_out_duration = 0.05
	route.black_hold_duration = 0.01
	route.fade_in_duration = 0.05
	route.blur_clear_duration = 0.05
	assert(route.request_transition(true))
	await create_timer(0.35).timeout
	# Select on the street, retaining the item and consuming both halves of E.
	await _aim(player, street_panel, 1)
	assert(player._weather_button() == street_panel.buttons[1])
	var item = game.get_node("PickupTestItem")
	player._pick_up_item(item)
	_press_e(player, true)
	_press_e(player, false)
	assert(weather.mode == 1 and player.held_item == item and not player.e_hold_pending)
	assert(street_panel.lights[1].emission != Color.BLACK)
	await create_timer(0.6).timeout
	var halfway: Color = weather.sun.light_color
	assert(not halfway.is_equal_approx(weather.PRESETS[0].sun_color))
	assert(not halfway.is_equal_approx(weather.PRESETS[1].sun_color), "Weather changed instantly")
	paused = true
	await create_timer(0.2).timeout
	assert(weather.sun.light_color.is_equal_approx(halfway), "Weather blend continued during pause")
	paused = false
	await create_timer(1.1).timeout
	assert(weather.sun.light_color.is_equal_approx(weather.PRESETS[1].sun_color))
	assert(camera.environment == weather.environment)
	assert(is_equal_approx(game.get_node("OmniLight3D").light_energy, original_lab_energy))
	# No distant, hidden, paused or busy interactions.
	await _aim(player, street_panel, 2, 4.0)
	assert(player._weather_button() == null)
	await _aim(player, street_panel, 2)
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.6
	collision.shape = shape
	blocker.add_child(collision)
	game.add_child(blocker)
	blocker.global_position = camera.global_position.lerp(street_panel.buttons[2].global_position, 0.5)
	await physics_frame
	await physics_frame
	assert(player._weather_button() == null)
	blocker.queue_free()
	await physics_frame
	await physics_frame
	player.swap_in_progress = true
	assert(player._weather_button() == null)
	player.swap_in_progress = false
	for lock in ["location_transition_active", "cutscene_active", "developer_tools_open"]:
		player.set_meta(lock, true)
		assert(player._weather_button() == null)
		player.remove_meta(lock)
	paused = true
	assert(player._weather_button() == null)
	paused = false
	# Exercise all presets; return restores the default state.
	camera.transform = original_camera_transform
	assert(route.request_transition(false))
	await create_timer(0.35).timeout
	assert(camera.environment == original_environment)
	for mode in range(4):
		weather.set_weather(mode)
		await create_timer(1.7).timeout
		assert(route.request_transition(true))
		await create_timer(0.35).timeout
		assert(weather.in_street and camera.environment == weather.environment)
		assert(weather.street.visible and weather.sun.is_visible_in_tree())
		assert(street_panel.is_visible_in_tree())
		assert(weather.mode == mode and not route.transitioning)
		assert(weather.rain.emitting == (mode == 3))
		assert(weather.rain_sound.playing == (mode == 3))
		if mode == 3:
			weather._lightning_strike()
			assert(weather.thunder_remaining > 0 and weather.flash_light.light_energy > 0)
			paused = true
			var delay: float = weather.thunder_remaining
			await create_timer(0.15).timeout
			assert(is_equal_approx(weather.thunder_remaining, delay))
			paused = false
			await create_timer(delay + 0.1).timeout
			assert(weather.thunder_sound.playing, "Lightning did not produce delayed thunder")
		assert(route.request_transition(false))
		await create_timer(0.35).timeout
		assert(not weather.in_street and weather.mode == 0)
		assert(is_zero_approx(weather.rain_strength))
		assert(weather.sun.light_color.is_equal_approx(weather.PRESETS[0].sun_color))
		assert(not weather.street.visible and not weather.sun.is_visible_in_tree())
		assert(not weather.flash_light.is_visible_in_tree() and not street_panel.is_visible_in_tree())
		assert(camera.environment == original_environment)
		assert(is_equal_approx(game.get_node("OmniLight3D").light_energy, original_lab_energy))
		assert(not weather.rain.emitting and not weather.rain.visible)
		assert(not weather.rain_sound.playing and not weather.thunder_sound.playing)
		assert(weather.thunder_remaining < 0 and is_zero_approx(weather.flash_light.light_energy))
	# Fast changes cancel thunder and converge on the last preset.
	assert(route.request_transition(true))
	await create_timer(0.35).timeout
	assert(weather.mode == 0 and not weather.rain.emitting)
	weather.set_weather(3)
	await create_timer(1.7).timeout
	weather._lightning_strike()
	weather.set_weather(1)
	weather.set_weather(2)
	weather.set_weather(0)
	assert(weather.thunder_remaining < 0)
	await create_timer(1.7).timeout
	assert(weather.mode == 0 and weather.rain_strength < 0.001)
	assert(not weather.rain.emitting and not weather.rain_sound.playing)
	assert(weather.sun.light_color.is_equal_approx(weather.PRESETS[0].sun_color))
	# The street console still works after returning.
	await _aim(player, street_panel, 2)
	assert(player._weather_button() == street_panel.buttons[2])
	_press_e(player, true)
	_press_e(player, false)
	assert(weather.mode == 2 and street_panel.lights[2].emission != Color.BLACK)
	menu._return_to_main_menu()
	await scene_changed
	await process_frame
	assert(current_scene.get_node("StreetWeather").mode == 0, "Weather persisted across scene restart")
	print("PASS: street-only console, weather presets, E priority, occlusion/range/locks, roofs, transitions, rain, thunder, pause and reset")
	quit()

func _aim(player: Node3D, panel: Node3D, index: int, distance: float = 2.0) -> void:
	player.global_position = panel.global_position + panel.global_basis.z * distance + Vector3(0, 0.92, 0)
	player.velocity = Vector3.ZERO
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	camera.look_at(panel.buttons[index].global_position)
	await physics_frame
	await physics_frame

func _press_e(player: Node, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.pressed = pressed
	player._unhandled_input(event)
