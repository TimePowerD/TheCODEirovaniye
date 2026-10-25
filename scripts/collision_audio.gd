extends AudioStreamPlayer3D

const IMPACT_STREAM: AudioStream = preload("res://assets/audio/final sounds/block_impact.mp3")

@export var minimum_impact_speed: float = 1.2
@export var impact_cooldown_ms: int = 140

var last_impact_time_ms: int = 0
var has_played_impact: bool = false

func _ready() -> void:
	unit_size = 8.0
	max_distance = 32.0
	stream = IMPACT_STREAM
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	body.contact_monitor = true
	body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
	body.body_entered.connect(_on_body_entered)

func _on_body_entered(_other_body: Node) -> void:
	var body := get_parent() as RigidBody3D
	if body == null or body.freeze:
		return
	var impact_speed := body.linear_velocity.length()
	if impact_speed < minimum_impact_speed:
		return
	var now_ms := Time.get_ticks_msec()
	if has_played_impact and now_ms - last_impact_time_ms < impact_cooldown_ms:
		return
	last_impact_time_ms = now_ms
	has_played_impact = true
	volume_db = lerpf(-15.0, -4.0, clampf((impact_speed - minimum_impact_speed) / 7.0, 0.0, 1.0))
	pitch_scale = randf_range(0.94, 1.06)
	play()
