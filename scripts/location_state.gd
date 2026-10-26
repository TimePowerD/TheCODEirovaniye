extends Node

signal location_changed(location_id: String)

var current_location_id := "laboratory"
var initial_player_transform := Transform3D.IDENTITY
var safe_player_transform := Transform3D.IDENTITY
var tracked_player: CharacterBody3D
var safe_body_transforms: Dictionary = {}

const FALL_RESPAWN_Y := -1.5

func initialize_scene(player: CharacterBody3D) -> void:
	initial_player_transform = player.global_transform
	safe_player_transform = player.global_transform
	tracked_player = player
	safe_body_transforms.clear()
	var scene := get_tree().current_scene
	if scene != null:
		for body in scene.find_children("*", "PhysicsBody3D", true, false):
			if body != player:
				safe_body_transforms[body] = body.global_transform
	set_current_location("laboratory")

func _physics_process(_delta: float) -> void:
	for body in safe_body_transforms.keys():
		if not is_instance_valid(body):
			safe_body_transforms.erase(body)
			continue
		if body.global_position.y < FALL_RESPAWN_Y:
			_restore_body(body)
		elif body is RigidBody3D:
			if not body.freeze and (body.sleeping or (body.linear_velocity.length_squared() < 0.0025 and body.angular_velocity.length_squared() < 0.0025)):
				safe_body_transforms[body] = body.global_transform
		else:
			safe_body_transforms[body] = body.global_transform

func save_player_safe_transform(player: CharacterBody3D) -> void:
	if is_instance_valid(player) and player.is_on_floor():
		safe_player_transform = player.global_transform

func restore_player_to_safe_position(player: CharacterBody3D) -> void:
	if not is_instance_valid(player):
		return
	player.global_transform = safe_player_transform
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()

func set_player_safe_transform(player: CharacterBody3D, safe_transform: Transform3D) -> void:
	if tracked_player == player:
		safe_player_transform = safe_transform

func _restore_body(body: PhysicsBody3D) -> void:
	body.global_transform = safe_body_transforms[body]
	if body is RigidBody3D:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = true
		body.reset_physics_interpolation()
	if body.has_method("reset_state"):
		body.call_deferred("reset_state")

func set_current_location(location_id: String) -> void:
	if current_location_id == location_id:
		return
	current_location_id = location_id
	location_changed.emit(location_id)
