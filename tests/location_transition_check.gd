extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var error := change_scene_to_file("res://scenes/main.tscn")
	assert(error == OK, "Main scene could not be loaded")
	await scene_changed
	var scene := current_scene
	await process_frame
	scene.get_node("MainMenu")._start_game()
	var player = scene.get_node("Player")
	var transition = scene.get_node("LocationTransition")
	var menu = scene.get_node("MainMenu")
	assert(transition.ambience == scene.get_node("FlashbackTransition").ambience, "Duplicate ambience")
	assert(transition.veil.get_parent().layer < menu.layer, "Transition covers pause menu")
	for marker in [transition.get_node("LaboratoryExit"), scene.get_node("FlashbackTransition/LaboratoryExit"), scene.get_node("CityRoom/ReturnArea"), scene.get_node("FlashbackRoom/ReturnArea")]:
		assert(marker.get_script() != null, "Transition marker script is missing")
		assert(marker.get_node_or_null("EditorCube") == null, "Marker cube is visible in game")
		assert(marker.get_node_or_null("EditorCaption") == null, "Editor caption leaked into game")
	assert(scene.get_node("FlashbackTransition/LaboratoryExit").transition_style == 1)
	assert(scene.get_node("FlashbackRoom/ReturnArea").transition_style == 1)
	assert(scene.get_node("MediumSphere") is RigidBody3D, "Main physics changes were lost")
	assert(scene.get_node("LargeCylinder") is RigidBody3D)
	var item = scene.get_node("PickupTestItem")
	player._pick_up_item(item)
	player.held_object = scene.get_node("MediumSphere")
	player.add_collision_exception_with(player.held_object)
	player._set_rotation_mode(true)
	player.e_hold_pending = true
	player._set_placement_mode(true)
	await physics_frame
	player.global_position = Vector3(0, 0.92, 19)
	player.swap_in_progress = true
	await create_timer(0.15).timeout
	assert(not transition.transitioning, "Transition interrupted swap")
	player.swap_in_progress = false
	await create_timer(transition.fade_out_duration * 0.5).timeout
	assert(transition.transitioning and not player.is_physics_processing())
	assert(not transition.in_city, "Player moved before blackout")
	var darkness: float = transition.fade_material.get_shader_parameter("darkness")
	assert(darkness > 0.0 and darkness < 1.0, "Fade did not progress gradually")
	menu._show_pause_menu()
	await process_frame
	var paused_darkness: float = transition.fade_material.get_shader_parameter("darkness")
	await create_timer(0.15).timeout
	assert(is_equal_approx(paused_darkness, transition.fade_material.get_shader_parameter("darkness")))
	menu._return_to_checkpoint()
	assert(paused, "Checkpoint reset bypassed active transition")
	menu._resume_game()
	await create_timer(transition.fade_out_duration * 0.5 + 0.15).timeout
	assert(transition.in_city, "Player was not moved under blackout")
	assert(is_equal_approx(transition.fade_material.get_shader_parameter("darkness"), 1.0))
	assert(not player.is_physics_processing(), "Controls restored during blackout")
	await create_timer(transition.black_hold_duration + transition.fade_in_duration + 0.2).timeout
	assert(transition.in_city, "Exit area did not transfer player into city")
	assert(player.global_position.x > 35, "Player did not reach separate room")
	assert(player.is_physics_processing(), "Player controls were not restored")
	assert(not transition.transitioning, "Transition did not complete")
	assert(transition.fade_material.get_shader_parameter("darkness") < 0.01, "Screen remained black")
	assert(player.held_object == null, "Physical grab remained attached across rooms")
	assert(not player.rotation_mode and not player.placement_mode and not player.e_hold_pending)
	assert(player.held_item == item and item.get_parent() == player.hand_anchor)
	assert(player.checkpoint_transform.origin.x > 35, "Checkpoint remained in laboratory")
	player.global_position = Vector3(40, 0.92, 6)
	await create_timer(transition.fade_out_duration + transition.black_hold_duration + transition.fade_in_duration + 0.3).timeout
	assert(not transition.in_city, "Return area did not transfer player into lab")
	assert(absf(player.global_position.x) < 1, "Incorrect return position")
	assert(player.global_position.z < 18, "Return spawn overlaps exit")
	assert(is_equal_approx(transition.laboratory_light.light_energy, transition.laboratory_energy))
	assert(player.is_physics_processing())
	assert(not paused)
	assert(player.held_item == item, "Carried item was lost on return")
	assert(absf(player.checkpoint_transform.origin.x) < 1)
	assert(transition.fade_material.get_shader_parameter("darkness") < 0.01)
	var memory = scene.get_node("FlashbackTransition")
	assert(memory.transition_style == 1)
	assert(not memory.veil.visible and not transition.veil.visible)
	player.global_position = Vector3(-6.6, 0.92, 4)
	await create_timer(memory.fade_out_duration * 0.5).timeout
	assert(memory.transitioning and not memory.in_city)
	assert(memory.veil.visible and not transition.veil.visible)
	assert(not player.is_physics_processing())
	assert(player.has_meta("location_transition_active"))
	assert(memory.fade_material.get_shader_parameter("darkness") > 0.0)
	assert(is_equal_approx(memory.laboratory_light.light_energy, memory.laboratory_energy))
	# The shared player lock prevents two controllers from running together.
	transition._on_exit(player, true)
	assert(not transition.transitioning)
	await create_timer(memory.fade_out_duration * 0.5 + 0.15).timeout
	assert(memory.in_city and player.global_position.x < -35)
	assert(is_equal_approx(memory.fade_material.get_shader_parameter("darkness"), 1.0))
	assert(is_equal_approx(memory.fade_material.get_shader_parameter("blur_amount"), 1.0))
	await create_timer(memory.black_hold_duration + memory.fade_in_duration + 0.2).timeout
	assert(memory.transitioning and memory.veil.visible)
	assert(player.is_physics_processing() and player.is_processing_unhandled_input())
	assert(player.has_meta("location_transition_active"))
	assert(memory.fade_material.get_shader_parameter("darkness") < 0.01)
	assert(memory.fade_material.get_shader_parameter("blur_amount") > 0.9)
	memory._on_exit(player, false)
	assert(memory.in_city, "Repeat transition bypassed blur lock")
	await create_timer(memory.blur_clear_duration * 0.5 - 0.35).timeout
	var remaining_blur: float = memory.fade_material.get_shader_parameter("blur_amount")
	assert(remaining_blur > 0.25 and remaining_blur < 0.75, "Blur did not decrease gradually")
	assert(memory.veil.visible and memory.transitioning)
	await create_timer(memory.blur_clear_duration * 0.5 + 0.2).timeout
	assert(not memory.transitioning and not memory.veil.visible)
	assert(memory.fade_material.get_shader_parameter("blur_amount") < 0.01)
	assert(player.is_physics_processing() and not player.has_meta("location_transition_active"))
	assert(memory.fade_material.get_shader_parameter("darkness") < 0.01)
	assert(player.held_item == item)
	player.global_position = Vector3(-40, 0.92, 6)
	await create_timer(memory.fade_out_duration + memory.black_hold_duration + memory.fade_in_duration + 0.3).timeout
	assert(memory.transitioning and memory.veil.visible)
	assert(not memory.in_city and player.is_physics_processing())
	assert(memory.fade_material.get_shader_parameter("darkness") < 0.01)
	assert(memory.fade_material.get_shader_parameter("blur_amount") > 0.9)
	await create_timer(memory.blur_clear_duration).timeout
	assert(not memory.in_city and not memory.transitioning)
	assert(memory.fade_material.get_shader_parameter("blur_amount") < 0.01)
	assert(absf(player.global_position.x + 4.8) < 0.3)
	assert(not memory.veil.visible and not player.has_meta("location_transition_active"))
	assert(player.is_physics_processing() and player.held_item == item)
	# Marker settings are authoritative, including different entry/return styles.
	memory.get_node("LaboratoryExit").transition_style = 0
	memory.fade_out_duration = 0.05
	memory.black_hold_duration = 0.01
	memory.fade_in_duration = 0.05
	memory.blur_clear_duration = 0.05
	memory._on_exit(player, true)
	await create_timer(0.3).timeout
	assert(memory.transition_style == 0 and memory.in_city)
	assert(memory.laboratory_light.light_energy < 0.01)
	memory._on_exit(player, false)
	await create_timer(0.4).timeout
	assert(memory.transition_style == 1 and not memory.in_city)
	assert(is_equal_approx(memory.laboratory_light.light_energy, memory.laboratory_energy))
	menu._return_to_main_menu()
	await scene_changed
	await process_frame
	assert(paused and not current_scene.get_node("MainMenu").game_started)
	assert(not current_scene.get_node("LocationTransition").in_city)
	assert(not current_scene.get_node("FlashbackTransition").in_city)
	assert(not current_scene.get_node("Player").has_meta("location_transition_active"))
	print("PASS: both routes, shared audio, deferred entry, pause, blur, markers, carried item and menu reset")
	quit()
