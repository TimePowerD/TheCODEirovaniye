extends CanvasLayer

@export var player: CharacterBody3D
@export var menu: CanvasLayer

const DOOR_OPEN_DISTANCE := 3.0
const DOOR_ANIMATION_DURATION := 0.9
const SUBTITLE_CHARACTER_INTERVAL := 0.045
const SUBTITLE_PERIOD_PAUSE := 0.3
const SUBTITLE_TASK_OFFSET := 1.5
const TUTORIAL_UI_DELAY := 2.0
const TUTORIAL_UI_FADE_DURATION := 0.7
const SUBTITLE_CLICK_STREAM: AudioStream = preload("res://assets/audio/audiointefsce/Audio/click3.ogg")
const NEXT_ROOM_TASK := "Пройдите в следующую комнату."
const FINAL_TASK := "Пройдите лабораторию."
const FINAL_SUBTITLE_DURATION := 5.0
const DOOR_OPEN_STREAM := preload("res://assets/audio/final sounds/lab_door_open.ogg")
const DIALOGUES := [
	"Привет. Теперь ты зомби. Попробуй подвигаться с помощью WASD.",
	"Теперь пройди в следующую комнату.",
	"Хорошо! Впереди препятствия. Перепрыгни их, нажимая пробел.",
	"Отлично! Теперь пройди в следующую комнату.",
	"Последний урок: удерживай ПКМ, чтобы передвинуть куб на кнопку. Можешь нажать её сам.",
	"Теперь пройди испытания.",
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
	get_node("../LabModuleLibrary/Props/TutorialDoor4") as Node3D,
	get_node("../LabModuleLibrary/Props/TutorialDoor5") as Node3D,
	get_node("../LabModuleLibrary/Props/TutorialDoor6") as Node3D,
]
@onready var button_sensor: Area3D = get_node("../LabModuleLibrary/Props/Button/ButtonSensor") as Area3D
@onready var next_level_button_sensor: Area3D = get_node_or_null("../LabModuleLibrary/Props/Button2/ButtonSensor") as Area3D
@onready var button3_sensor: Area3D = get_node_or_null("../LabModuleLibrary/Props/Button3/ButtonSensor") as Area3D
@onready var second_room_checkpoint: Area3D = get_node_or_null("../LevelCheckpoints/Level1Checkpoint") as Area3D
@onready var third_room_checkpoint: Area3D = get_node_or_null("../LevelCheckpoints/Level2Checkpoint") as Area3D

var step := 0
var line_index := 0
var task_override := ""
var training_finished := false
var show_completion_task := false
var final_subtitle_remaining := 0.0
var door_closed_positions: Array[Vector3] = []
var door_body_closed_positions: Array[Vector3] = []
var door_bodies: Array[AnimatableBody3D] = []
var door_open_sounds: Array[AudioStreamPlayer3D] = []
var door_tweens: Dictionary = {}
var tutorial_panel: PanelContainer
var tutorial_label: Label
var tutorial_heading: Label
var flashback_objective := ""
var flashback_subtitles_hidden := false
var subtitle_panel: PanelContainer
var speaker_label: Label
var subtitle_label: Label
var subtitle_typing_timer: Timer
var subtitle_transition_timer: Timer
var tutorial_ui_delay_timer: Timer
var subtitle_click_player: AudioStreamPlayer
var subtitle_full_text := ""
var subtitle_character_index := 0
var pending_subtitle_lines: Array[int] = []
var tutorial_ui_reveal_scheduled := false
var tutorial_ui_ready := false
var tutorial_ui_fade_started := false

func _ready() -> void:
	layer = 2
	_build_tutorial_panel()
	_build_subtitles()
	tutorial_panel.modulate.a = 0.0
	subtitle_panel.modulate.a = 0.0
	tutorial_panel.hide()
	subtitle_panel.hide()
	subtitle_transition_timer = Timer.new()
	subtitle_transition_timer.name = "SubtitleTransitionTimer"
	subtitle_transition_timer.one_shot = true
	subtitle_transition_timer.wait_time = SUBTITLE_TASK_OFFSET
	subtitle_transition_timer.timeout.connect(_on_subtitle_transition_timeout)
	add_child(subtitle_transition_timer)
	tutorial_ui_delay_timer = Timer.new()
	tutorial_ui_delay_timer.name = "TutorialUIRevealTimer"
	tutorial_ui_delay_timer.one_shot = true
	tutorial_ui_delay_timer.wait_time = TUTORIAL_UI_DELAY
	tutorial_ui_delay_timer.timeout.connect(_reveal_tutorial_ui)
	add_child(tutorial_ui_delay_timer)
	var wake_cutscene := get_node_or_null("../WakeCutscene")
	if wake_cutscene != null and wake_cutscene.has_signal("finished"):
		wake_cutscene.connect("finished", _on_wake_cutscene_finished)
	for door in doors:
		door_closed_positions.append(door.global_position)
		var door_body := door.get_node("DoorCollisionBody") as AnimatableBody3D
		door_bodies.append(door_body)
		door_body_closed_positions.append(door_body.global_position)
		var sound_player := AudioStreamPlayer3D.new()
		sound_player.name = "DoorOpenSound"
		sound_player.stream = DOOR_OPEN_STREAM
		sound_player.max_distance = 24.0
		door.add_child(sound_player)
		door_open_sounds.append(sound_player)
	player.gameplay_action.connect(_on_gameplay_action)
	button_sensor.pressed.connect(_on_button_pressed)
	button_sensor.released.connect(_on_button_released)
	if next_level_button_sensor != null:
		next_level_button_sensor.pressed.connect(_on_next_level_button_pressed)
		next_level_button_sensor.released.connect(_on_next_level_button_released)
	if button3_sensor != null:
		button3_sensor.pressed.connect(_on_button3_pressed)
	if second_room_checkpoint != null:
		second_room_checkpoint.body_entered.connect(_on_second_room_entered)
	if third_room_checkpoint != null:
		third_room_checkpoint.body_entered.connect(_on_third_room_entered)
	_update_tutorial_panel()
	_update_subtitles()

func restart() -> void:
	subtitle_transition_timer.stop()
	pending_subtitle_lines.clear()
	player.tutorial_walk_distance = 0.0
	step = 0
	line_index = 0
	task_override = ""
	training_finished = false
	show_completion_task = false
	final_subtitle_remaining = 0.0
	_set_door_open(0, false)
	_set_door_open(1, false)
	_set_door_open(2, false)
	_set_door_open(3, false)
	_set_door_open(4, false)
	_set_door_open(5, false)
	_update_tutorial_panel()
	_update_subtitles()

func complete() -> void:
	step = TASKS.size()
	task_override = ""
	training_finished = true
	show_completion_task = false
	_update_tutorial_panel()
	subtitle_panel.hide()

func _on_gameplay_action(action: StringName) -> void:
	if action == &"flashback_return":
		_set_door_open(3, true)
		return
	if not _can_progress() or training_finished:
		return
	if step == 0 and task_override.is_empty() and action == &"walk":
		task_override = NEXT_ROOM_TASK
		_set_door_open(0, true)
		_update_tutorial_panel()
		_queue_subtitle_line(1)
	elif step == 1 and task_override.is_empty() and action == &"jump" and _player_is_in_jump_room():
		task_override = NEXT_ROOM_TASK
		_set_door_open(1, true)
		_update_tutorial_panel()
		_queue_subtitle_line(3)

func _on_second_room_entered(body: Node3D) -> void:
	if body != player or not _can_progress() or training_finished or step != 0 or task_override != NEXT_ROOM_TASK:
		return
	step = 1
	task_override = ""
	line_index = 2
	_update_tutorial_panel()
	_update_subtitles()

func _on_third_room_entered(body: Node3D) -> void:
	if body != player or not _can_progress() or training_finished or step != 1 or task_override != NEXT_ROOM_TASK:
		return
	step = 2
	task_override = ""
	line_index = 4
	_update_tutorial_panel()
	_update_subtitles()

func _on_button_pressed() -> void:
	if training_finished:
		if _can_progress():
			_set_door_open(2, true)
		return
	if step != 2 or not _can_progress():
		return
	_set_door_open(2, true)
	training_finished = true
	show_completion_task = true
	step = TASKS.size()
	line_index = 5
	final_subtitle_remaining = FINAL_SUBTITLE_DURATION
	_update_tutorial_panel()
	_queue_subtitle_line(5)

func _on_next_level_button_pressed() -> void:
	_set_door_open(4, true)

func _on_next_level_button_released() -> void:
	_set_door_open(4, false)

func _on_button3_pressed() -> void:
	_set_door_open(5, true)

func _on_button_released() -> void:
	_set_door_open(2, false)
	pending_subtitle_lines.erase(5)
	subtitle_transition_timer.stop()
	if line_index == 5:
		line_index = 4
		_update_tutorial_panel()
		_update_subtitles()
	else:
		_schedule_next_subtitle_line()

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
	if should_open and index < door_open_sounds.size():
		door_open_sounds[index].play()
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
	tween.finished.connect(_save_world_door_state)

func _save_world_door_state() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.save_current_world_state()

func _process(delta: float) -> void:
	if not tutorial_ui_ready and not tutorial_ui_reveal_scheduled \
		and bool(menu.get("game_started")) and not bool(menu.get("start_with_cutscene")):
		_schedule_tutorial_ui_reveal()
	var can_show_ui := bool(menu.get("game_started")) \
		and not player.has_meta("developer_tools_open") \
		and not player.has_meta("cutscene_active") \
		and tutorial_ui_ready
	if can_show_ui and not tutorial_ui_fade_started:
		_fade_in_tutorial_ui(can_show_ui)
	if can_show_ui and final_subtitle_remaining > 0.0:
		final_subtitle_remaining = maxf(final_subtitle_remaining - delta, 0.0)
	tutorial_panel.visible = can_show_ui and (step < TASKS.size() or show_completion_task)
	subtitle_panel.visible = not flashback_subtitles_hidden and can_show_ui and (step < TASKS.size() or final_subtitle_remaining > 0.0)
	if not subtitle_panel.visible:
		subtitle_typing_timer.stop()
	elif subtitle_character_index == 0 and subtitle_label.text.is_empty():
		_start_subtitle_typing()
	elif subtitle_character_index < subtitle_full_text.length() and subtitle_typing_timer.is_stopped():
		subtitle_typing_timer.start()
	if tutorial_panel.visible:
		_update_tutorial_panel()

func _on_wake_cutscene_finished() -> void:
	_schedule_tutorial_ui_reveal()

func _schedule_tutorial_ui_reveal() -> void:
	if tutorial_ui_reveal_scheduled or tutorial_ui_ready:
		return
	tutorial_ui_reveal_scheduled = true
	tutorial_ui_delay_timer.start()

func _reveal_tutorial_ui() -> void:
	tutorial_ui_ready = true
	var can_show_ui := bool(menu.get("game_started")) \
		and not player.has_meta("developer_tools_open") \
		and not player.has_meta("cutscene_active")
	if can_show_ui:
		_fade_in_tutorial_ui(can_show_ui)

func _fade_in_tutorial_ui(can_show_ui: bool) -> void:
	if tutorial_ui_fade_started:
		return
	tutorial_ui_fade_started = true
	tutorial_panel.visible = can_show_ui and (step < TASKS.size() or show_completion_task)
	subtitle_panel.visible = not flashback_subtitles_hidden and can_show_ui and (step < TASKS.size() or final_subtitle_remaining > 0.0)
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(tutorial_panel, "modulate:a", 1.0, TUTORIAL_UI_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(subtitle_panel, "modulate:a", 1.0, TUTORIAL_UI_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
	tutorial_heading = Label.new()
	tutorial_heading.text = "ОБУЧЕНИЕ"
	tutorial_heading.add_theme_font_size_override("font_size", 13)
	tutorial_heading.add_theme_color_override("font_color", Color(0.52, 0.86, 0.82, 1.0))
	tutorial_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tutorial_heading)
	tutorial_label = Label.new()
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.add_theme_font_size_override("font_size", 17)
	tutorial_label.add_theme_color_override("font_color", Color(0.94, 0.97, 0.96, 1.0))
	tutorial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tutorial_label)
	add_child(tutorial_panel)

func _update_tutorial_panel() -> void:
	if not is_instance_valid(tutorial_label):
		return
	if not flashback_objective.is_empty():
		tutorial_heading.text = "ЦЕЛЬ"
		tutorial_label.text = flashback_objective
		return
	tutorial_heading.text = "ОБУЧЕНИЕ"
	if show_completion_task:
		tutorial_label.text = FINAL_TASK
		return
	if step >= TASKS.size():
		return
	var task: String = task_override if not task_override.is_empty() else TASKS[step]
	tutorial_label.text = "%d / %d\n%s" % [step + 1, TASKS.size(), task]
	if step == 2 and button_sensor.is_pressed:
		tutorial_label.text = "3 / 3\nКнопка нажата — дверь открыта."

func set_flashback_objective(objective: String) -> void:
	flashback_objective = objective
	_update_tutorial_panel()

func set_flashback_subtitles_hidden(hidden: bool) -> void:
	flashback_subtitles_hidden = hidden
	if hidden:
		if is_instance_valid(subtitle_panel):
			subtitle_panel.hide()
		if is_instance_valid(subtitle_typing_timer):
			subtitle_typing_timer.stop()

func seal_all_tutorial_doors() -> void:
	button_sensor.set_deferred("monitoring", false)
	for index in range(doors.size()):
		_set_door_open(index, false)
	_update_tutorial_panel()

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
	subtitle_typing_timer = Timer.new()
	subtitle_typing_timer.name = "SubtitleTypingTimer"
	subtitle_typing_timer.wait_time = SUBTITLE_CHARACTER_INTERVAL
	subtitle_typing_timer.timeout.connect(_reveal_next_subtitle_character)
	add_child(subtitle_typing_timer)
	subtitle_click_player = AudioStreamPlayer.new()
	subtitle_click_player.name = "SubtitleTypingSound"
	subtitle_click_player.stream = SUBTITLE_CLICK_STREAM
	subtitle_click_player.volume_db = -18.0
	subtitle_click_player.max_polyphony = 3
	add_child(subtitle_click_player)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.add_child(column)
	speaker_label = Label.new()
	speaker_label.text = "Доктор"
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
	subtitle_typing_timer.stop()
	subtitle_label.text = ""
	subtitle_full_text = DIALOGUES[line_index]
	subtitle_character_index = 0
	subtitle_typing_timer.wait_time = SUBTITLE_CHARACTER_INTERVAL

func _start_subtitle_typing() -> void:
	if subtitle_character_index == 0 and subtitle_label.text.is_empty():
		_reveal_next_subtitle_character()
	if subtitle_character_index < subtitle_full_text.length() and subtitle_typing_timer.is_stopped():
		subtitle_typing_timer.start()

func _reveal_next_subtitle_character() -> void:
	if subtitle_character_index >= subtitle_full_text.length():
		subtitle_typing_timer.stop()
		_schedule_next_subtitle_line()
		return
	var character := subtitle_full_text.substr(subtitle_character_index, 1)
	subtitle_label.text += character
	if not character.strip_edges().is_empty():
		subtitle_click_player.play()
	subtitle_character_index += 1
	if subtitle_character_index >= subtitle_full_text.length():
		subtitle_typing_timer.stop()
		_schedule_next_subtitle_line()
	else:
		subtitle_typing_timer.wait_time = SUBTITLE_PERIOD_PAUSE if character == "." else SUBTITLE_CHARACTER_INTERVAL

func _queue_subtitle_line(next_line: int) -> void:
	if next_line == line_index or pending_subtitle_lines.has(next_line):
		return
	pending_subtitle_lines.append(next_line)
	_schedule_next_subtitle_line()

func _schedule_next_subtitle_line() -> void:
	if pending_subtitle_lines.is_empty() or not is_instance_valid(subtitle_transition_timer):
		return
	if subtitle_character_index < subtitle_full_text.length() or not subtitle_typing_timer.is_stopped():
		return
	if subtitle_transition_timer.is_stopped():
		subtitle_transition_timer.start(SUBTITLE_TASK_OFFSET)

func _on_subtitle_transition_timeout() -> void:
	if pending_subtitle_lines.is_empty():
		return
	var next_line: int = pending_subtitle_lines.pop_front()
	if next_line == 5 and not button_sensor.is_pressed:
		_schedule_next_subtitle_line()
		return
	line_index = next_line
	_update_subtitles()
