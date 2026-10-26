extends Node3D

@onready var door_visual: Node3D = $DoorVisual
@onready var door_body: AnimatableBody3D = $DoorCollisionBody

const PLATE_PATH := NodePath("../CubeWeightPuzzle/WeightPlate")
const OPEN_DISTANCE := 3.0
const OPEN_DURATION := 0.9
const DOOR_OPEN_STREAM := preload("res://assets/audio/final sounds/lab_door_open.ogg")

var closed_visual_position := Vector3.ZERO
var closed_body_position := Vector3.ZERO
var opening_tween: Tween
var is_open := false
var door_open_sound: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("saveable_door")
	closed_visual_position = door_visual.global_position
	closed_body_position = door_body.global_position
	door_open_sound = AudioStreamPlayer3D.new()
	door_open_sound.name = "DoorOpenSound"
	door_open_sound.stream = DOOR_OPEN_STREAM
	door_open_sound.volume_db = 0.0
	door_open_sound.pitch_scale = 1.0
	door_open_sound.max_distance = 24.0
	add_child(door_open_sound)
	var plate := get_node_or_null(PLATE_PATH)
	if plate == null:
		push_error("Weight puzzle door can't find its pressure plate.")
		return
	if plate.has_signal("activated"):
		plate.activated.connect(open_door)
	if bool(plate.get("is_active")):
		open_door()

func open_door() -> void:
	if is_open:
		return
	is_open = true
	if is_instance_valid(door_open_sound):
		door_open_sound.play()
	if opening_tween != null and opening_tween.is_running():
		opening_tween.kill()
	var open_offset := Vector3(0.0, 0.0, OPEN_DISTANCE)
	opening_tween = create_tween().set_parallel(true)
	opening_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	opening_tween.tween_property(door_visual, "global_position", closed_visual_position + open_offset, OPEN_DURATION)
	opening_tween.tween_property(door_body, "global_position", closed_body_position + open_offset, OPEN_DURATION)
	opening_tween.finished.connect(_save_open_state)

func reset_state() -> void:
	if opening_tween != null and opening_tween.is_running():
		opening_tween.kill()
	is_open = false
	door_visual.global_position = closed_visual_position
	door_body.global_position = closed_body_position

func _save_open_state() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.save_current_world_state()
