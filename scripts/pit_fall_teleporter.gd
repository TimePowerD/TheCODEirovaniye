extends Area3D

@export var safe_position: Node3D

var teleporting := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if teleporting or not body.is_in_group("player") or not body is CharacterBody3D:
		return
	if safe_position == null or not is_instance_valid(safe_position):
		push_error("Pit return zone has no safe position assigned.")
		return

	teleporting = true
	var player := body as CharacterBody3D
	player.velocity = Vector3.ZERO
	player.global_transform = safe_position.global_transform
	get_node("/root/LocationState").set_player_safe_transform(player, player.global_transform)
	player.reset_physics_interpolation()
	player.clear_swap_selection()
	await get_tree().physics_frame
	teleporting = false
