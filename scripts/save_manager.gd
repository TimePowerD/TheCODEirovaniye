extends Node

signal checkpoint_restored(location_id: String)

const SAVE_PATH := "user://savegame.cfg"
const FALL_RESPAWN_Y := -3.0

var current_location_id := "laboratory"
var checkpoint_id := "level_start"
var initial_player_transform := Transform3D.IDENTITY
var initial_camera_rotation := Vector3.ZERO
var initial_object_states: Dictionary = {}
var initial_door_states: Dictionary = {}

func _physics_process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node_path in initial_object_states:
		var body := scene.get_node_or_null(node_path) as RigidBody3D
		if body != null and body.global_position.y < FALL_RESPAWN_Y:
			restore_object_to_initial(body)

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
	initial_door_states = _capture_door_states(scene)

func reset_world_to_initial() -> void:
	for node_path in initial_object_states:
		var body := get_tree().current_scene.get_node_or_null(node_path) as PhysicsBody3D
		if body == null:
			continue
		restore_object_to_initial(body)
	_apply_door_states(get_tree().current_scene, initial_door_states)

func restore_object_to_initial(body: PhysicsBody3D) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.is_ancestor_of(body):
		return
	var node_path := scene.get_path_to(body)
	if not initial_object_states.has(node_path):
		return
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

func save_object_checkpoint(body: RigidBody3D) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.is_ancestor_of(body):
		return
	var node_path := scene.get_path_to(body)
	if not initial_object_states.has(node_path):
		return
	var state: Dictionary = initial_object_states[node_path]
	state["transform"] = body.global_transform
	initial_object_states[node_path] = state

func restore_player(player: CharacterBody3D) -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	var current_scene := get_tree().current_scene
	if current_scene == null or config.get_value("checkpoint", "scene", "") != current_scene.scene_file_path:
		return false
	reset_world_to_initial()
	var saved_door_states: Dictionary = config.get_value("world", "doors", {})
	call_deferred("_apply_saved_world_state", current_scene, saved_door_states, config.get_value("world", "objects", {}))
	var position: Vector3 = config.get_value("checkpoint", "position", player.global_position)
	var rotation: Vector3 = config.get_value("checkpoint", "rotation", player.rotation)
	var camera_rotation: Vector3 = config.get_value("checkpoint", "camera_rotation", player.camera_pivot.rotation)
	player.global_transform = Transform3D(Basis.from_euler(rotation), position)
	player.checkpoint_transform = player.global_transform
	player.camera_pivot.rotation = camera_rotation
	player.checkpoint_camera_rotation = camera_rotation
	current_location_id = str(config.get_value("checkpoint", "location", "laboratory"))
	checkpoint_id = str(config.get_value("checkpoint", "id", "level_start"))
	checkpoint_restored.emit(current_location_id)
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
	var held_item := player.get("held_item") as RigidBody3D
	if held_item != null:
		save_object_checkpoint(held_item)
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
	config.set_value("world", "doors", _capture_door_states(get_tree().current_scene))
	config.set_value("world", "objects", _capture_object_states(get_tree().current_scene))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить точку возрождения: %s" % error_string(error))

func set_location(location_id: String) -> void:
	current_location_id = location_id

func save_current_world_state() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	config.set_value("world", "doors", _capture_door_states(get_tree().current_scene))
	config.set_value("world", "objects", _capture_object_states(get_tree().current_scene))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить состояние дверей: %s" % error_string(error))

func restore_world_state() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var scene := get_tree().current_scene
	if scene == null or config.get_value("checkpoint", "scene", "") != scene.scene_file_path:
		return
	call_deferred("_apply_saved_world_state", scene, config.get_value("world", "doors", {}), config.get_value("world", "objects", {}))

func _capture_object_states(scene: Node) -> Dictionary:
	var states: Dictionary = {}
	if scene == null:
		return states
	for object in get_tree().get_nodes_in_group("swappable"):
		if not is_instance_valid(object) or not scene.is_ancestor_of(object) or not object is PhysicsBody3D:
			continue
		var state := {"transform": object.global_transform}
		if object is RigidBody3D:
			state["freeze"] = object.freeze
			for property in object.get_property_list():
				if property.name == "physics_enabled":
					state["physics_enabled"] = object.get("physics_enabled")
					break
		states[str(scene.get_path_to(object))] = state
	return states

func _apply_saved_world_state(scene: Node, doors: Dictionary, objects: Dictionary) -> void:
	_apply_door_states(scene, doors)
	for object_path in objects:
		var object := scene.get_node_or_null(NodePath(str(object_path))) as PhysicsBody3D
		if object == null:
			continue
		var state: Dictionary = objects[object_path]
		if object is RigidBody3D:
			object.freeze = true
		object.global_transform = state.get("transform", object.global_transform)
		if object is RigidBody3D:
			object.linear_velocity = Vector3.ZERO
			object.angular_velocity = Vector3.ZERO
			if state.get("physics_enabled") != null:
				object.set("physics_enabled", state["physics_enabled"])
			object.freeze = bool(state.get("freeze", false))
		object.reset_physics_interpolation()
		var initial_state: Dictionary = initial_object_states.get(NodePath(str(object_path)), {})
		initial_state["transform"] = object.global_transform
		if state.get("physics_enabled") != null:
			initial_state["physics_enabled"] = state["physics_enabled"]
		initial_object_states[NodePath(str(object_path))] = initial_state

func _capture_door_states(scene: Node) -> Dictionary:
	var states: Dictionary = {}
	if scene == null:
		return states
	for door in get_tree().get_nodes_in_group("saveable_door"):
		if not is_instance_valid(door) or not scene.is_ancestor_of(door):
			continue
		var part_states: Dictionary = {}
		var parts: Array[Node3D] = [door as Node3D]
		for part in door.find_children("*", "Node3D", true, false):
			if part.name in ["DoorVisual", "DoorCollisionBody"]:
				parts.append(part as Node3D)
		for part in parts:
			part_states[str(scene.get_path_to(part))] = part.global_transform
		var state := {"parts": part_states}
		for property in door.get_property_list():
			if property.name == "is_open":
				state["is_open"] = bool(door.get("is_open"))
				break
		states[str(scene.get_path_to(door))] = state
	return states

func _apply_door_states(scene: Node, states: Dictionary) -> void:
	if scene == null:
		return
	for door_path in states:
		var state: Dictionary = states[door_path]
		var parts: Dictionary = state.get("parts", {})
		for part_path in parts:
			var part := scene.get_node_or_null(NodePath(str(part_path))) as Node3D
			if part != null and parts[part_path] is Transform3D:
				part.global_transform = parts[part_path]
		var door := scene.get_node_or_null(NodePath(str(door_path)))
		if door != null and state.has("is_open"):
			door.set("is_open", bool(state["is_open"]))
