extends CanvasLayer

signal finished

## Opening first-person wake-up sequence. The scientist can be added later at the
## final look direction without changing the camera choreography.

@export var player_path: NodePath = ^"../Player"
@export_range(0.25, 5.0, 0.05) var skip_hold_duration := 1.2

@onready var player: CharacterBody3D = get_node(player_path)

var running := false
var skip_in_progress := false
var eyelid: ColorRect
var lower_eyelid: ColorRect
var skip_panel: PanelContainer
var skip_progress: ProgressBar
var skip_elapsed := 0.0
var sequence: Tween
var pivot: Node3D
var original_position := Vector3.ZERO
var original_rotation := Vector3.ZERO
var original_body_yaw := 0.0
var original_player_position := Vector3.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("developer_cutscenes")
	layer = 20
	eyelid = _create_eyelid("UpperEyelid")
	eyelid.anchor_bottom = 0.5
	lower_eyelid = _create_eyelid("LowerEyelid")
	lower_eyelid.anchor_top = 0.5
	_build_skip_indicator()
	hide()

func _create_eyelid(lid_name: String) -> ColorRect:
	var lid := ColorRect.new()
	lid.name = lid_name
	lid.color = Color.BLACK
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lid.offset_left = 0.0
	lid.offset_top = 0.0
	lid.offset_right = 0.0
	lid.offset_bottom = 0.0
	add_child(lid)
	return lid

func _set_eyes_closed() -> void:
	eyelid.anchor_bottom = 0.5
	lower_eyelid.anchor_top = 0.5

func _animate_eyes(tween: Tween, open: bool, duration: float) -> void:
	var upper_target := 0.0 if open else 0.5
	var lower_target := 1.0 if open else 0.5
	tween.tween_property(eyelid, "anchor_bottom", upper_target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(lower_eyelid, "anchor_top", lower_target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	if not running or skip_in_progress:
		return
	var holding_space := Input.is_key_pressed(KEY_SPACE)
	skip_panel.visible = true
	if holding_space:
		skip_elapsed = minf(skip_elapsed + delta, skip_hold_duration)
	else:
		skip_elapsed = 0.0
	skip_progress.value = skip_elapsed
	if skip_elapsed >= skip_hold_duration:
		_skip()

func _build_skip_indicator() -> void:
	skip_panel = PanelContainer.new()
	skip_panel.name = "SkipPrompt"
	skip_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_panel.offset_left = -330.0
	skip_panel.offset_top = -88.0
	skip_panel.offset_right = -28.0
	skip_panel.offset_bottom = -24.0
	skip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.025, 0.78)
	style.border_color = Color(0.65, 0.78, 0.72, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	skip_panel.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	skip_panel.add_child(layout)
	var label := Label.new()
	label.text = "УДЕРЖИВАЙТЕ ПРОБЕЛ — ПРОПУСТИТЬ"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	layout.add_child(label)
	skip_progress = ProgressBar.new()
	skip_progress.min_value = 0.0
	skip_progress.max_value = skip_hold_duration
	skip_progress.show_percentage = false
	skip_progress.custom_minimum_size.y = 8.0
	skip_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(skip_progress)
	add_child(skip_panel)
	skip_panel.hide()

func play() -> void:
	if running or not is_instance_valid(player):
		return
	running = true
	skip_in_progress = false
	skip_elapsed = 0.0
	skip_progress.max_value = skip_hold_duration
	skip_progress.value = 0.0
	show()
	player.set_meta("cutscene_active", true)
	player._release_object()
	player.e_hold_pending = false
	player._set_placement_mode(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	pivot = player.get_node("CameraPivot") as Node3D
	original_player_position = player.global_position
	original_position = pivot.position
	original_rotation = pivot.rotation
	original_body_yaw = player.rotation.y
	pivot.position.y = 0.3
	pivot.rotation.x = deg_to_rad(-12.0)
	_set_eyes_closed()

	sequence = create_tween()
	sequence.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	# Open slowly at first, then make two relaxed, readable blinks.
	_animate_eyes(sequence, true, 1.35)
	sequence.tween_interval(0.55)
	_animate_eyes(sequence, false, 0.24)
	sequence.tween_interval(0.10)
	_animate_eyes(sequence, true, 0.48)
	sequence.tween_interval(0.8)
	_animate_eyes(sequence, false, 0.26)
	sequence.tween_interval(0.12)
	_animate_eyes(sequence, true, 0.52)
	sequence.tween_interval(0.65)
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
	_animate_eyes(sequence, false, 0.22)
	sequence.tween_interval(0.12)
	_animate_eyes(sequence, true, 0.5)
	sequence.finished.connect(_finish)

func _skip() -> void:
	if not running or skip_in_progress:
		return
	skip_in_progress = true
	if sequence != null and sequence.is_running():
		sequence.kill()
	pivot.position = original_position
	pivot.rotation = original_rotation
	player.rotation.y = original_body_yaw
	_set_eyes_closed()
	skip_panel.hide()
	var fade := create_tween()
	_animate_eyes(fade, true, 0.3)
	fade.finished.connect(_finish)

func _finish() -> void:
	if not is_instance_valid(player):
		return
	player.global_position = original_player_position
	player.remove_meta("cutscene_active")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	player.reset_interaction_modes()
	running = false
	skip_in_progress = false
	skip_elapsed = 0.0
	skip_panel.hide()
	hide()
	finished.emit()
