extends SceneTree

var game: Node
var player: CharacterBody3D
var tutorial: CanvasLayer
var menu: CanvasLayer

func _initialize() -> void:
	call_deferred("_check")

func _advance(action: StringName, trigger: Callable, delay := 0.05) -> void:
	assert(tutorial.ACTIONS[tutorial.step] == action, "Wrong tutorial order")
	trigger.call()
	await create_timer(delay).timeout
	assert(tutorial.completed, "Action did not complete tutorial: %s" % action)
	await create_timer(1.3).timeout

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	game = current_scene
	player = game.get_node("Player")
	tutorial = game.get_node("Tutorial")
	menu = game.get_node("MainMenu")
	menu._start_game()
	await create_timer(0.2).timeout
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	await _advance(&"look", player.apply_look.bind(motion.relative))
	player.rotation = Vector3.ZERO
	player.global_position = Vector3(4, 0.92, 4)
	player.velocity = Vector3.ZERO
	_key(KEY_W, true)
	await create_timer(0.5).timeout
	_key(KEY_W, false)
	assert(tutorial.completed)
	await create_timer(1.3).timeout
	player.global_position = Vector3(4, 0.92, 4)
	player.velocity = Vector3.ZERO
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	await create_timer(0.4).timeout
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	assert(tutorial.completed)
	await create_timer(1.3).timeout
	await _advance(&"jump", _key.bind(KEY_SPACE, true), 0.1)
	_key(KEY_SPACE, false)
	var box = game.get_node("SmallBox")
	box.freeze = true
	player.global_position = Vector3(4, 0.92, 4)
	player.velocity = Vector3.ZERO
	box.global_position = Vector3(4, 1.3, 2)
	await physics_frame
	player.aim_ray.force_raycast_update()
	await _advance(&"grab", player._try_grab_object)
	player.held_object = box
	player._set_rotation_mode(true)
	player._set_rotation_axis(0)
	player.rotation_speed = 1.0
	await _advance(&"rotate", player._update_held_rotation.bind(0.1))
	player.held_object = box
	await _advance(&"release_grab", player._release_object)
	var item = game.get_node("PickupTestItem")
	await _advance(&"pickup", player._pick_up_item.bind(item))
	await _advance(&"use", player._use_held_item)
	player.placement_valid = true
	player.placement_position = Vector3(4, 0, 2)
	player.placement_normal = Vector3.UP
	await _advance(&"place", player._place_held_item)
	await _advance(&"pickup", player._pick_up_item.bind(item))
	await _advance(&"throw", player._throw_item)
	player.hovered_target = box
	await _advance(&"select_swap", player._handle_swap_click)
	# Physics highlight may change the hovered target between clicks.
	player.hovered_target = game.get_node("SwapTestObject")
	await _advance(&"swap", player._handle_swap_click, player.swap_duration + 0.1)
	await _advance(&"pause_resume", func():
		menu._show_pause_menu()
		menu._resume_game())
	await _advance(&"checkpoint", menu._return_to_checkpoint)
	for route_name in ["LocationTransition", "FlashbackTransition"]:
		var route = game.get_node(route_name)
		route.fade_out_duration = 0.05
		route.black_hold_duration = 0.01
		route.fade_in_duration = 0.05
		route.blur_clear_duration = 0.05
		var entering: StringName = &"location_enter" if route_name == "LocationTransition" else &"flashback_enter"
		var returning: StringName = &"location_return" if route_name == "LocationTransition" else &"flashback_return"
		await _advance(entering, route.request_transition.bind(true), 0.3)
		await _advance(returning, route.request_transition.bind(false), 0.3)
	assert(tutorial.step == tutorial.ACTIONS.size())
	print("PASS: all 20 tutorial tasks triggered by gameplay mechanics")
	quit()
