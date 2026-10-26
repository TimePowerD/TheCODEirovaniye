extends PathFollow3D
## Slow ambient traffic follows a closed lane and brakes for physical obstacles.
const MOTOR_STREAM: AudioStream = preload("res://assets/audio/final sounds/motor_looping.mp3")

@export var cruise_speed: float = 5.0
var speed := 0.0
var probe := BoxShape3D.new()
@onready var body: AnimatableBody3D = $Body
var motor_player: AudioStreamPlayer3D

func _ready() -> void:
	probe.size = Vector3(1.85, 1.6, 3.7)
	var motor_stream := MOTOR_STREAM.duplicate() as AudioStreamMP3
	motor_stream.loop = true
	motor_player = AudioStreamPlayer3D.new()
	motor_player.name = "MotorLoop"
	motor_player.stream = motor_stream
	motor_player.volume_db = -9.0
	motor_player.unit_size = 8.0
	motor_player.max_distance = 55.0
	body.add_child(motor_player)
	motor_player.play()

func _physics_process(delta: float) -> void:
	if not is_visible_in_tree():
		if motor_player.playing:
			motor_player.stop()
		return
	if not motor_player.playing:
		motor_player.play()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = body.global_transform
	query.transform.origin += Vector3.UP * 1.0 - global_basis.z * 3.0
	query.collision_mask = 3
	query.exclude = [body.get_rid()]
	var blocked := not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	speed = move_toward(speed, 0.0 if blocked else cruise_speed, (14.0 if blocked else 2.0) * delta)
	progress += speed * delta

