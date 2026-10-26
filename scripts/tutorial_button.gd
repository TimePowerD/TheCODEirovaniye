extends Area3D

signal pressed
signal released

const PRESS_SOUND: AudioStream = preload("res://assets/audio/final sounds/menu_click.mp3")
const PLAYER_GROUP: StringName = &"player"
const MINIMUM_ACTIVATOR_MASS := 1.0
const PRESS_DURATION := 0.18
const HITBOX_LOWER_DISTANCE := 0.045

var is_pressed := false
var activating_bodies: Array[Node3D] = []
var button_visual: MeshInstance3D
var sensor_hitbox: CollisionShape3D
var physical_hitbox: CollisionShape3D
var sensor_hitbox_rest_position := Vector3.ZERO
var physical_hitbox_rest_position := Vector3.ZERO
var sound_player: AudioStreamPlayer3D
var button_tween: Tween

func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	button_visual = get_parent().get_node_or_null("Cube_001") as MeshInstance3D
	sensor_hitbox = $CollisionShape3D
	sensor_hitbox_rest_position = sensor_hitbox.position
	physical_hitbox = get_parent().get_node("ButtonCollisionBody/CollisionShape3D") as CollisionShape3D
	physical_hitbox_rest_position = physical_hitbox.position
	sound_player = AudioStreamPlayer3D.new()
	sound_player.name = "PressSound"
	sound_player.stream = PRESS_SOUND
	sound_player.volume_db = -6.0
	add_child(sound_player)

func _physics_process(_delta: float) -> void:
	var detected_bodies: Array[Node3D] = []
	for body in get_overlapping_bodies():
		if _is_activator(body):
			detected_bodies.append(body)
	activating_bodies = detected_bodies
	_update_pressed_state()

func _on_body_entered(body: Node3D) -> void:
	if not _is_activator(body) or activating_bodies.has(body):
		return
	activating_bodies.append(body)
	_update_pressed_state()

func _on_body_exited(body: Node3D) -> void:
	if not activating_bodies.has(body):
		return
	activating_bodies.erase(body)
	_update_pressed_state()

func _is_activator(body: Node3D) -> bool:
	if body.is_in_group(PLAYER_GROUP):
		return true
	if not body is RigidBody3D or (body as RigidBody3D).mass < MINIMUM_ACTIVATOR_MASS:
		return false
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return true
	return false

func _update_pressed_state() -> void:
	var next_state := not activating_bodies.is_empty()
	if next_state == is_pressed:
		return
	is_pressed = next_state
	_animate_button(next_state)
	if is_pressed:
		sound_player.play()
		pressed.emit()
	else:
		released.emit()

func _animate_button(should_press: bool) -> void:
	if button_tween != null and button_tween.is_running():
		button_tween.kill()
	var blend_target := 1.0 if should_press else 0.0
	var sensor_target := sensor_hitbox_rest_position
	var physical_target := physical_hitbox_rest_position
	if should_press:
		sensor_target.y -= HITBOX_LOWER_DISTANCE
		physical_target.y -= HITBOX_LOWER_DISTANCE
	button_tween = create_tween().set_parallel(true)
	button_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(button_visual):
		button_tween.tween_property(button_visual, "blend_shapes/Key 1", blend_target, PRESS_DURATION)
	button_tween.tween_property(sensor_hitbox, "position", sensor_target, PRESS_DURATION)
	button_tween.tween_property(physical_hitbox, "position", physical_target, PRESS_DURATION)
