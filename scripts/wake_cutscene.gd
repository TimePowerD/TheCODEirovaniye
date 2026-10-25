extends CanvasLayer

## Opening first-person wake-up sequence. The scientist can be added later at the
## final look direction without changing the camera choreography.

@export var player_path: NodePath = ^"../Player"

@onready var player: CharacterBody3D = get_node(player_path)

var running := false
var eyelid: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	eyelid = ColorRect.new()
	eyelid.name = "EyelidOverlay"
	eyelid.color = Color.BLACK
	eyelid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyelid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(eyelid)
	hide()

func play() -> void:
	if running or not is_instance_valid(player):
		return
	running = true
	show()
	player.set_meta("cutscene_active", true)
	player._release_object()
	player.e_hold_pending = false
	player._set_placement_mode(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var pivot := player.get_node("CameraPivot") as Node3D
	var original_position := pivot.position
	var original_rotation := pivot.rotation
	var original_body_yaw := player.rotation.y
	pivot.position.y = 0.3
	pivot.rotation.x = deg_to_rad(-12.0)
	eyelid.modulate.a = 1.0

	var sequence := create_tween()
	sequence.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	# First slow opening, then two brief blinks.
	sequence.tween_property(eyelid, "modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	sequence.tween_interval(0.45)
	sequence.tween_property(eyelid, "modulate:a", 1.0, 0.10)
	sequence.tween_interval(0.12)
	sequence.tween_property(eyelid, "modulate:a", 0.0, 0.24)
	sequence.tween_interval(0.7)
	sequence.tween_property(eyelid, "modulate:a", 1.0, 0.09)
	sequence.tween_interval(0.10)
	sequence.tween_property(eyelid, "modulate:a", 0.0, 0.22)
	# Raise the viewpoint and let the player take in the room.
	sequence.tween_property(pivot, "position:y", original_position.y, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sequence.parallel().tween_property(pivot, "rotation:x", deg_to_rad(-5.0), 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sequence.tween_interval(0.35)
	sequence.tween_property(player, "rotation:y", original_body_yaw + deg_to_rad(-38.0), 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_interval(0.25)
	sequence.tween_property(player, "rotation:y", original_body_yaw + deg_to_rad(32.0), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_interval(0.25)
	sequence.tween_property(player, "rotation:y", original_body_yaw, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_property(pivot, "rotation:x", original_rotation.x, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	sequence.tween_interval(0.35)
	sequence.tween_property(eyelid, "modulate:a", 1.0, 0.12)
	sequence.tween_interval(0.16)
	sequence.tween_property(eyelid, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE)
	sequence.finished.connect(_finish)

func _finish() -> void:
	if not is_instance_valid(player):
		return
	player.remove_meta("cutscene_active")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	player.reset_interaction_modes()
	running = false
	hide()
