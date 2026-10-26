extends Area3D

@export var destination_location_id := "kitchen"
@export var destination_transform := Transform3D.IDENTITY

var transitioning := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	if destination_transform == Transform3D.IDENTITY:
		destination_transform = _resolve_destination_transform()
	if OS.is_debug_build():
		_add_debug_visual()

func _resolve_destination_transform() -> Transform3D:
	var scene := get_tree().current_scene
	if destination_location_id == "laboratory":
		return get_node("/root/SaveManager").initial_player_transform
	if destination_location_id == "transition_room":
		var marker := scene.get_node_or_null("LocationTransition/LaboratoryArrival") as Node3D
		return marker.global_transform if marker != null else Transform3D.IDENTITY
	var room_name := ""
	match destination_location_id:
		"city": room_name = "CityRoom"
		"flashback": room_name = "FlashbackRoom"
		"forest": room_name = "ForestRoom"
		"kitchen": room_name = "KitchenRoom"
		_:
			return Transform3D.IDENTITY
	var room := scene.find_child(room_name, true, false)
	var arrival: Node3D
	if room != null:
		arrival = room.find_child("Arrival", true, false) as Node3D
	return arrival.global_transform if arrival != null else Transform3D.IDENTITY

func _add_debug_visual() -> void:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return
	var visual := MeshInstance3D.new()
	visual.name = "DebugVisual"
	var box := BoxMesh.new()
	box.size = (shape_node.shape as BoxShape3D).size
	visual.mesh = box
	visual.position = shape_node.position
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.8, 1.0, 0.22)
	visual.material_override = material
	add_child(visual)

func _on_body_entered(body: Node3D) -> void:
	if transitioning or not body.is_in_group("player") or not body is CharacterBody3D:
		return
	var player := body as CharacterBody3D
	if player.swap_in_progress or player.has_meta("location_transition_active") \
		or player.has_meta("cutscene_active") or player.has_meta("developer_tools_open"):
		return
	if destination_transform == Transform3D.IDENTITY:
		destination_transform = _resolve_destination_transform()
	if destination_transform == Transform3D.IDENTITY:
		push_error("Location teleport trigger has no valid destination transform.")
		return
	transitioning = true
	player.set_meta("location_transition_active", true)
	player._release_object()
	player._drop_item()
	player.e_hold_pending = false
	player.e_hold_elapsed = 0.0
	player._set_placement_mode(false)
	player.velocity = Vector3.ZERO
	player.clear_swap_selection()
	player.global_transform = destination_transform
	player.camera_pivot.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	var save_manager := get_node("/root/SaveManager")
	save_manager.save_player_checkpoint(
		player,
		"trigger_%s" % destination_location_id,
		destination_location_id,
		destination_transform
	)
	save_manager.checkpoint_restored.emit(destination_location_id)
	await get_tree().physics_frame
	player.remove_meta("location_transition_active")
	transitioning = false
