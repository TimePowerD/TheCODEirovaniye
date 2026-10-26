extends Area3D

const NORMAL_TRANSITION_SOUND: AudioStream = preload("res://assets/audio/final sounds/location_teleport.mp3")

@export var destination_location_id := "kitchen"
@export var destination_transform := Transform3D.IDENTITY
@export var use_visual_transition := false
@export var show_debug_visual := true
@export_enum("Обычный переход", "Флэшбэк") var transition_style := 0
@export_range(0.1, 5.0, 0.05) var fade_out_duration := 1.2
@export_range(0.0, 3.0, 0.05) var hold_duration := 0.65
@export_range(0.1, 5.0, 0.05) var fade_in_duration := 2.0
@export_range(0.1, 10.0, 0.05) var blur_clear_duration := 3.0

var transitioning := false
var used_while_inside := false
var veil: ColorRect
var fade_material: ShaderMaterial
var transition_sound: AudioStreamPlayer

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if destination_transform == Transform3D.IDENTITY:
		destination_transform = _resolve_destination_transform()
	if use_visual_transition:
		_create_overlay()
		transition_sound = AudioStreamPlayer.new()
		transition_sound.name = "TransitionSound"
		transition_sound.stream = NORMAL_TRANSITION_SOUND
		transition_sound.volume_db = -6.0
		add_child(transition_sound)
	if show_debug_visual and OS.is_debug_build():
		_add_debug_visual()

func _create_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_material = ShaderMaterial.new()
	fade_material.shader = preload("res://scripts/flashback_fade.gdshader") if transition_style == 1 else preload("res://scripts/location_fade.gdshader")
	fade_material.set_shader_parameter("darkness", 0.0)
	if transition_style == 1:
		fade_material.set_shader_parameter("blur_amount", 0.0)
	veil.material = fade_material
	layer.add_child(veil)
	veil.hide()

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
	material.albedo_color = Color(1.0, 0.8, 0.35, 0.22) if use_visual_transition and transition_style == 1 else Color(0.15, 0.8, 1.0, 0.22)
	visual.material_override = material
	add_child(visual)

func _physics_process(_delta: float) -> void:
	if transitioning or used_while_inside:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			return

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		used_while_inside = false

func _on_body_entered(body: Node3D) -> void:
	if transitioning or used_while_inside or not body.is_in_group("player") or not body is CharacterBody3D:
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
	used_while_inside = true
	player.set_meta("location_transition_active", true)
	player._release_object()
	player._drop_item()
	player.e_hold_pending = false
	player.e_hold_elapsed = 0.0
	player._set_placement_mode(false)
	player.velocity = Vector3.ZERO
	player.clear_swap_selection()
	if use_visual_transition:
		var was_physics_processing := player.is_physics_processing()
		var was_input_processing := player.is_processing_unhandled_input()
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		transition_sound.play()
		await _play_visual_transition(player, was_physics_processing, was_input_processing)
	else:
		_teleport_player(player)
		await get_tree().physics_frame
	player.remove_meta("location_transition_active")
	transitioning = false

func _teleport_player(player: CharacterBody3D) -> void:
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

func _play_visual_transition(player: CharacterBody3D, was_physics_processing: bool, was_input_processing: bool) -> void:
	veil.show()
	var fade := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(fade_material, "shader_parameter/darkness", 1.0, fade_out_duration)
	if transition_style == 1:
		fade.tween_property(fade_material, "shader_parameter/blur_amount", 1.0, fade_out_duration)
	await fade.finished
	_teleport_player(player)
	await get_tree().create_timer(hold_duration, false).timeout
	var reveal := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(fade_material, "shader_parameter/darkness", 0.0, fade_in_duration)
	await reveal.finished
	if transition_style == 1:
		var clear_blur := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		clear_blur.tween_property(fade_material, "shader_parameter/blur_amount", 0.0, blur_clear_duration)
		await clear_blur.finished
	veil.hide()
	await _after_visual_transition_reveal(player)
	player.set_physics_process(was_physics_processing)
	player.set_process_unhandled_input(was_input_processing)

func _after_visual_transition_reveal(_player: CharacterBody3D) -> void:
	await get_tree().process_frame
