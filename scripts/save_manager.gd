extends Node

const SAVE_PATH := "user://savegame.cfg"

var current_location_id := "laboratory"
var checkpoint_id := "level_start"
var initial_player_transform := Transform3D.IDENTITY
var initial_camera_rotation := Vector3.ZERO
var initial_object_states: Dictionary = {}

func capture_scene_start(player: CharacterBody3D) -> void:
	initial_player_transform = player.global_transform
	initial_camera_rotation = player.camera_pivot.rotation
	initial_object_states.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	for body in scene.find_children("*", "PhysicsBody3D", true, false):
		var physics_enabled: Variant = null
		if body is RigidBody3D:
			for property in body.get_property_list():
				if property.name == "physics_enabled":
					physics_enabled = body.get("physics_enabled")
					break
		initial_object_states[scene.get_path_to(body)] = {
			"transform": body.global_transform,
			"physics_enabled": physics_enabled,
		}

func reset_world_to_initial() -> void:
	for node_path in initial_object_states:
		var body := get_tree().current_scene.get_node_or_null(node_path) as PhysicsBody3D
		if body == null:
			continue
		var state: Dictionary = initial_object_states[node_path]
		body.global_transform = state.transform
		if state.physics_enabled != null:
			body.set("physics_enabled", state.physics_enabled)
		if body is RigidBody3D:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true
			body.reset_physics_interpolation()
		if body.has_method("reset_state"):
			body.call_deferred("reset_state")

func restore_player(player: CharacterBody3D) -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	var current_scene := get_tree().current_scene
	if current_scene == null or config.get_value("checkpoint", "scene", "") != current_scene.scene_file_path:
		return false
	reset_world_to_initial()
	var position: Vector3 = config.get_value("checkpoint", "position", player.global_position)
	var rotation: Vector3 = config.get_value("checkpoint", "rotation", player.rotation)
	var camera_rotation: Vector3 = config.get_value("checkpoint", "camera_rotation", player.camera_pivot.rotation)
	player.global_transform = Transform3D(Basis.from_euler(rotation), position)
	player.checkpoint_transform = player.global_transform
	player.camera_pivot.rotation = camera_rotation
	player.checkpoint_camera_rotation = camera_rotation
	current_location_id = str(config.get_value("checkpoint", "location", "laboratory"))
	checkpoint_id = str(config.get_value("checkpoint", "id", "level_start"))
	return true

func has_valid_checkpoint() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	var scene := get_tree().current_scene
	return scene != null and config.get_value("checkpoint", "scene", "") == scene.scene_file_path

func clear_checkpoint() -> void:
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)
	checkpoint_id = "level_start"
	current_location_id = "laboratory"

func start_new_game(player: CharacterBody3D) -> void:
	clear_checkpoint()
	reset_world_to_initial()
	player.global_transform = initial_player_transform
	player.camera_pivot.rotation = initial_camera_rotation
	player.velocity = Vector3.ZERO
	player.checkpoint_transform = initial_player_transform
	player.checkpoint_camera_rotation = initial_camera_rotation
	player.reset_interaction_modes()
	save_player_checkpoint(player, "level_start", "laboratory")

func save_player_checkpoint(player: CharacterBody3D, id: String, location_id: String = "", spawn_transform: Variant = null) -> void:
	if not is_instance_valid(player):
		return
	if not location_id.is_empty():
		current_location_id = location_id
	checkpoint_id = id
	var checkpoint_transform: Transform3D = player.global_transform if spawn_transform == null else spawn_transform
	player.checkpoint_transform = checkpoint_transform
	player.checkpoint_camera_rotation = player.camera_pivot.rotation
	var config := ConfigFile.new()
	config.set_value("checkpoint", "scene", get_tree().current_scene.scene_file_path)
	config.set_value("checkpoint", "id", checkpoint_id)
	config.set_value("checkpoint", "location", current_location_id)
	config.set_value("checkpoint", "position", checkpoint_transform.origin)
	config.set_value("checkpoint", "rotation", checkpoint_transform.basis.get_euler())
	config.set_value("checkpoint", "camera_rotation", player.camera_pivot.rotation)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить точку возрождения: %s" % error_string(error))

func set_location(location_id: String) -> void:
	current_location_id = location_id
