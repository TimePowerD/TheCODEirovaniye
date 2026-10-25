extends Area3D

@export var checkpoint_id := "checkpoint"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or not body is CharacterBody3D:
		return
	var spawn_point := get_node_or_null("SpawnPoint") as Marker3D
	var spawn_transform: Transform3D = spawn_point.global_transform if spawn_point != null else body.global_transform
	get_node("/root/SaveManager").save_player_checkpoint(body, checkpoint_id, "", spawn_transform)
