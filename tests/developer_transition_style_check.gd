extends SceneTree

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
	var player := game.get_node("Player") as CharacterBody3D
	var tools := game.get_node("DeveloperTools")
	var menu := game.get_node("MainMenu")
	menu.start_with_cutscene = false
	menu._start_game()
	assert(tools.trigger_effect_picker.item_count == 2)
	var forest_index := -1
	for index in range(tools.locations.size()):
		if tools.locations[index].location_id == "forest":
			forest_index = index
			break
	assert(forest_index >= 0)
	for style in [0, 1]:
		player.global_transform = root.get_node("SaveManager").initial_player_transform
		player.velocity = Vector3.ZERO
		await physics_frame
		tools.toggle()
		assert(tools.opened)
		tools.trigger_destination_picker.select(forest_index)
		tools.trigger_effect_picker.select(style)
		tools.place_location_trigger()
		var trigger := tools.objects.back() as Area3D
		assert(trigger != null and trigger.use_visual_transition)
		assert(trigger.transition_style == style and trigger.destination_location_id == "forest")
		assert(trigger.fade_material.shader.resource_path == ("res://scripts/flashback_fade.gdshader" if style == 1 else "res://scripts/location_fade.gdshader"))
		assert(trigger.transition_sound.stream.resource_path == "res://assets/audio/final sounds/location_teleport.mp3")
		if style == 1:
			assert(trigger.transition_sound.stream == game.get_node("ForestTransition").TRANSITION_STREAM)
			assert(is_equal_approx(trigger.fade_out_duration, 1.6) and is_equal_approx(trigger.hold_duration, 0.8) and is_equal_approx(trigger.fade_in_duration, 2.8))
		else:
			assert(is_equal_approx(trigger.fade_out_duration, 1.2) and is_equal_approx(trigger.hold_duration, 0.65) and is_equal_approx(trigger.fade_in_duration, 2.0))
		trigger.fade_out_duration = 0.25
		trigger.hold_duration = 0.05
		trigger.fade_in_duration = 0.25
		trigger.blur_clear_duration = 0.2
		tools.close()
		player.global_position = trigger.global_position - Vector3.UP * 0.58
		await create_timer(0.12).timeout
		assert(trigger.transitioning and trigger.veil.visible, "Trigger did not start the selected effect")
		assert(not player.is_physics_processing())
		if style == 1:
			assert(trigger.fade_material.get_shader_parameter("blur_amount") > 0.0)
		await create_timer(0.8).timeout
		assert(not trigger.transitioning and not trigger.veil.visible)
		assert(root.get_node("SaveManager").current_location_id == "forest")
		assert(player.global_position.distance_to(game.get_node("ForestRoom/Arrival").global_position) < 0.1)
		assert(is_zero_approx(trigger.fade_material.get_shader_parameter("darkness")))
		if style == 1:
			assert(is_zero_approx(trigger.fade_material.get_shader_parameter("blur_amount")))
		tools.objects.erase(trigger)
		trigger.queue_free()
		await process_frame
		tools._teleport_to_location("laboratory", root.get_node("SaveManager").initial_player_transform)
		await physics_frame
	var kitchen_trigger := preload("res://scenes/kitchen_transition_trigger.tscn").instantiate()
	assert(not kitchen_trigger.use_visual_transition, "Existing kitchen trigger changed behavior")
	kitchen_trigger.free()
	print("PASS: developer trigger selects dark or flashback effect; kitchen trigger remains instant")
	quit()
