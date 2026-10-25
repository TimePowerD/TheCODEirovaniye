extends Node

@export var player: CharacterBody3D
var running := false
var camera: Camera3D
var original_camera: Camera3D
var motion: Tween

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	add_to_group("developer_cutscenes")

func play() -> void:
	if running or player.has_meta("location_transition_active") or player.has_meta("cutscene_active") or player.swap_in_progress:
		return
	running = true
	player.set_meta("cutscene_active", true)
	player._release_object()
	player.e_hold_pending = false
	player._set_placement_mode(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	original_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	add_child(camera)
	camera.global_transform = original_camera.global_transform
	camera.fov = original_camera.fov
	camera.make_current()
	var start := camera.global_transform
	var finish := start
	finish.origin += start.basis.x * 2.0 + Vector3.UP * 0.7
	motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(camera, "global_transform", finish, 2.0)
	motion.tween_property(camera, "global_transform", start, 2.0)
	motion.finished.connect(stop)

func stop() -> void:
	if not running:
		return
	if motion != null:
		motion.kill()
	if is_instance_valid(original_camera):
		original_camera.make_current()
	if is_instance_valid(camera):
		camera.queue_free()
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	player.remove_meta("cutscene_active")
	running = false

func _unhandled_input(event: InputEvent) -> void:
	if running and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		stop()
		get_viewport().set_input_as_handled()
