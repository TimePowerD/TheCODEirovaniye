extends Area3D

@onready var spawn_point: Marker3D = $SpawnPoint

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		get_node("/root/SaveManager").save_object_checkpoint(body)
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("clear_swap_selection"):
		body.clear_swap_selection()
	if body.has_method("return_to_checkpoint"):
		body.set("checkpoint_transform", spawn_point.global_transform)
		get_node("/root/SaveManager").save_player_checkpoint(
			body,
			name,
			"laboratory",
			spawn_point.global_transform
		)
