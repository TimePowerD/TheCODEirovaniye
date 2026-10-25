extends CanvasLayer

@export var player: CharacterBody3D
@export var menu: CanvasLayer

const DOOR_OPEN_DISTANCE := 3.0
const DOOR_ANIMATION_DURATION := 0.9
const DIALOGUES := [
	"Привет. Теперь ты зомби. Попробуй подвигаться с помощью WASD.",
	"Хорошо! Впереди препятствия. Перепрыгни их, нажимая пробел.",
	"Последний урок: удерживай ПКМ, чтобы передвинуть куб на кнопку. Можешь нажать её сам.",
	"Отлично. Дверь открыта, пока кнопка нажата.",
]
const TASKS := [
	"WASD — подвигайся, чтобы открыть первую дверь.",
	"Пробел — перепрыгни препятствия, чтобы открыть вторую дверь.",
	"Удерживай ПКМ и передвинь куб на кнопку. Дверь открыта, пока кнопка нажата.",
]

@onready var doors: Array[Node3D] = [
	get_node("../LabModuleLibrary/Props/Door") as Node3D,
	get_node("../LabModuleLibrary/Props/TutorialDoor2") as Node3D,
	get_node("../LabModuleLibrary/Props/TutorialDoor3") as Node3D,
]
@onready var button_sensor: Area3D = get_node("../LabModuleLibrary/Props/Button/ButtonSensor") as Area3D

var step := 0
var line_index := 0
var door_closed_positions: Array[Vector3] = []
var door_body_closed_positions: Array[Vector3] = []
var door_bodies: Array[AnimatableBody3D] = []
var door_tweens: Dictionary = {}
var tutorial_panel: PanelContainer
var tutorial_label: Label
var subtitle_panel: PanelContainer
var speaker_label: Label
var subtitle_label: Label

func _ready() -> void:
	layer = 2
	_build_tutorial_panel()
	_build_subtitles()
	for door in doors:
		door_closed_positions.append(door.global_position)
		var door_body := door.get_node("DoorCollisionBody") as AnimatableBody3D
		door_bodies.append(door_body)
		door_body_closed_positions.append(door_body.global_position)
	player.gameplay_action.connect(_on_gameplay_action)
	button_sensor.pressed.connect(_on_button_pressed)
	button_sensor.released.connect(_on_button_released)
	restart()

func restart() -> void:
	player.tutorial_walk_distance = 0.0
	step = 0
	line_index = 0
	_set_door_open(0, false)
	_set_door_open(1, false)
	_update_tutorial_panel()
	_update_subtitles()

func _on_gameplay_action(action: StringName) -> void:
	if not _can_progress():
		return
	if step == 0 and action == &"walk":
		step = 1
		line_index = 1
		_set_door_open(0, true)
		_update_tutorial_panel()
		_update_subtitles()
	elif step == 1 and action == &"jump" and _player_is_in_jump_room():
		step = 2
		line_index = 2
		_set_door_open(1, true)
		_update_tutorial_panel()
		_update_subtitles()

func _on_button_pressed() -> void:
	if step < 2:
		return
	_set_door_open(2, true)
	line_index = 3
	_update_tutorial_panel()
	_update_subtitles()

func _on_button_released() -> void:
	_set_door_open(2, false)
	if line_index == 3:
		line_index = 2
		_update_tutorial_panel()
		_update_subtitles()

func _can_progress() -> bool:
	return menu.game_started and not get_tree().paused \
		and not player.has_meta("developer_tools_open") \
		and not player.has_meta("cutscene_active") \
		and not player.has_meta("location_transition_active")

func _player_is_in_jump_room() -> bool:
	return player.global_position.x >= 135.4 and player.global_position.x <= 153.5 \
		and player.global_position.z >= 171.0 and player.global_position.z <= 203.5

func _set_door_open(index: int, should_open: bool) -> void:
	if index >= doors.size() or not is_instance_valid(doors[index]):
		return
	var door := doors[index]
	var target_position := door_closed_positions[index]
	var target_body_position := door_body_closed_positions[index]
	if should_open:
		target_position.z += DOOR_OPEN_DISTANCE
		target_body_position.z += DOOR_OPEN_DISTANCE
	var current_tween: Tween = door_tweens.get(index)
	if current_tween != null and current_tween.is_running():
		current_tween.kill()
	var tween := create_tween()
	door_tweens[index] = tween
	var visual_tweener := tween.tween_property(door, "global_position", target_position, DOOR_ANIMATION_DURATION)
	visual_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var collision_tweener := tween.parallel().tween_property(
		door_bodies[index], "global_position", target_body_position, DOOR_ANIMATION_DURATION
	)
	collision_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(_delta: float) -> void:
	var can_show_ui: bool = menu.game_started \
		and not player.has_meta("developer_tools_open") \
		and not player.has_meta("cutscene_active")
	tutorial_panel.visible = can_show_ui and step < TASKS.size()
	subtitle_panel.visible = can_show_ui and (step < TASKS.size() or line_index == 3)
	if tutorial_panel.visible:
		_update_tutorial_panel()

func _build_tutorial_panel() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "TutorialTaskPanel"
	tutorial_panel.position = Vector2(24.0, 24.0)
	tutorial_panel.custom_minimum_size = Vector2(340.0, 0.0)
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.06, 0.9)
	style.border_color = Color(0.52, 0.76, 0.72, 0.8)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(7)
	tutorial_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.add_child(column)
	var heading := Label.new()
	heading.text = "ОБУЧЕНИЕ"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(0.52, 0.86, 0.82, 1.0))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	tutorial_label = Label.new()
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.add_theme_font_size_override("font_size", 17)
	tutorial_label.add_theme_color_override("font_color", Color(0.94, 0.97, 0.96, 1.0))
	tutorial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tutorial_label)
	add_child(tutorial_panel)

func _update_tutorial_panel() -> void:
	if not is_instance_valid(tutorial_label) or step >= TASKS.size():
		return
	tutorial_label.text = "%d / %d\n%s" % [step + 1, TASKS.size(), TASKS[step]]
	if step == 2 and button_sensor.is_pressed:
		tutorial_label.text = "3 / 3\nКнопка нажата — дверь открыта."

func _build_subtitles() -> void:
	subtitle_panel = PanelContainer.new()
	subtitle_panel.name = "NarratorSubtitles"
	subtitle_panel.anchor_left = 0.5
	subtitle_panel.anchor_right = 0.5
	subtitle_panel.anchor_top = 1.0
	subtitle_panel.anchor_bottom = 1.0
	subtitle_panel.offset_left = -430.0
	subtitle_panel.offset_right = 430.0
	subtitle_panel.offset_top = -120.0
	subtitle_panel.offset_bottom = -24.0
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.05, 0.88)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(8)
	subtitle_panel.add_theme_stylebox_override("panel", style)
	add_child(subtitle_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.add_child(column)
	speaker_label = Label.new()
	speaker_label.text = "РАССКАЗЧИК"
	speaker_label.add_theme_font_size_override("font_size", 13)
	speaker_label.add_theme_color_override("font_color", Color(0.52, 0.86, 0.82, 1.0))
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(speaker_label)
	subtitle_label = Label.new()
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 20)
	subtitle_label.add_theme_color_override("font_color", Color(0.94, 0.97, 0.96, 1.0))
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(subtitle_label)

func _update_subtitles() -> void:
	if not is_instance_valid(subtitle_label):
		return
	subtitle_label.text = DIALOGUES[line_index]
