extends SceneTree
## Windowed preview: run only after explicit user permission.
func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	root.size = Vector2i(1280, 720)
	root.always_on_top = true
	root.grab_focus()
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var scene := current_scene
	scene.get_node("MainMenu")._start_game()
	var route = scene.get_node("FlashbackTransition")
	route.fade_out_duration = 0.1
	route.black_hold_duration = 0.01
	route.fade_in_duration = 0.1
	route.blur_clear_duration = 0.1
	assert(route.request_transition(true))
	await create_timer(0.7).timeout
	var weather = scene.get_node("StreetWeather")
	var player = scene.get_node("Player")
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	camera.look_at(Vector3(-40, 2.3, -23))
	# Keep movement available; free the cursor for this automated preview.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for mode in range(4):
		weather.set_weather(mode)
		root.title = "Погода: " + weather.PRESETS[mode].title
		await create_timer(2.0).timeout
		if mode == 3:
			weather._lightning_strike()
			await create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/weather-preview-%d.png" % mode)
		await create_timer(2.0).timeout
	print("PASS: rendered four weather presets with OpenGL; previews saved in .godot")
	quit()
