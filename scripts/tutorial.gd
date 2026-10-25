extends CanvasLayer

@export var player: CharacterBody3D
@export var menu: CanvasLayer
const ACTIONS := [&"walk", &"jump", &"pickup", &"swap"]
const COMPLETION_DELAY := 1.2
const SKIP_HOLD_DURATION := 1.0
const TASKS := [
	"WASD — пройдите один метр",
	"Пробел — прыгните",
	"E — возьмите предмет в руку или удерживайте ПКМ — захватите физический объект",
	"Освободите руки: Q / отпустите ПКМ. ЛКМ — выберите два видимых объекта для обмена",
]
var step := 0
var completed := false
var progress := 0.0
var pending_actions: Array[StringName] = []
var label: Label
var panel: PanelContainer
var skip_panel: PanelContainer
var skip_progress: ProgressBar
var skip_elapsed := 0.0

func _ready() -> void:
	layer = 2
	panel = PanelContainer.new()
	panel.position = Vector2(16, 62)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.065, 0.075, 0.9)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	label = Label.new()
	label.custom_minimum_size.x = 310
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_build_skip_prompt()
	player.gameplay_action.connect(_on_action)
	restart()

func _build_skip_prompt() -> void:
	skip_panel = PanelContainer.new()
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
	var prompt := Label.new()
	prompt.text = "УДЕРЖИВАЙТЕ ПРОБЕЛ — ПРОПУСТИТЬ ОБУЧЕНИЕ"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt.add_theme_font_size_override("font_size", 12)
	layout.add_child(prompt)
	skip_progress = ProgressBar.new()
	skip_progress.max_value = SKIP_HOLD_DURATION
	skip_progress.show_percentage = false
	skip_progress.custom_minimum_size.y = 8.0
	skip_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(skip_progress)
	add_child(skip_panel)
	skip_panel.hide()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.keycode != KEY_SPACE:
		return
	if event.pressed and not event.echo and menu.game_started and step < ACTIONS.size() and not get_tree().paused and not player.has_meta("cutscene_active"):
		player.set_meta("tutorial_skip_hold", true)
	elif not event.pressed:
		player.remove_meta("tutorial_skip_hold")

func _sync_jump_step_meta() -> void:
	if step < ACTIONS.size() and ACTIONS[step] == &"jump":
		player.set_meta("tutorial_jump_step", true)
	else:
		player.remove_meta("tutorial_jump_step")

func restart() -> void:
	player.remove_meta("tutorial_skip_hold")
	player.remove_meta("tutorial_jump_step")
	player.tutorial_walk_distance = 0.0
	pending_actions.clear()
	step = 0
	completed = false
	progress = 0.0
	_sync_jump_step_meta()
	_update_text()

func skip() -> void:
	pending_actions.clear()
	completed = false
	progress = 0.0
	step = ACTIONS.size()
	skip_elapsed = 0.0
	player.remove_meta("tutorial_jump_step")
	panel.hide()
	skip_panel.hide()
	if not Input.is_key_pressed(KEY_SPACE):
		player.remove_meta("tutorial_skip_hold")

func _on_action(action: StringName) -> void:
	if step >= ACTIONS.size() or not menu.game_started or get_tree().paused:
		return
	if player.has_meta("developer_tools_open") or player.has_meta("cutscene_active") or player.has_meta("location_transition_active"):
		return
	if action == &"grab":
		action = &"pickup"
	if completed:
		var expected_index := step + 1 + pending_actions.size()
		if expected_index < ACTIONS.size() and action == ACTIONS[expected_index]:
			pending_actions.append(action)
		return
	if action != ACTIONS[step]:
		return
	completed = true
	progress = 0.0
	_update_text()

func _process(delta: float) -> void:
	var visible_task: bool = menu.game_started and not get_tree().paused and not player.has_meta("developer_tools_open") and not player.has_meta("cutscene_active") and not player.has_meta("location_transition_active")
	panel.visible = visible_task and step < ACTIONS.size()
	_sync_jump_step_meta()
	var holding_skip := visible_task and step < ACTIONS.size() and Input.is_key_pressed(KEY_SPACE)
	skip_panel.visible = visible_task and step < ACTIONS.size()
	if holding_skip:
		player.set_meta("tutorial_skip_hold", true)
		skip_elapsed = minf(skip_elapsed + delta, SKIP_HOLD_DURATION)
		if skip_elapsed >= SKIP_HOLD_DURATION:
			skip()
	else:
		skip_elapsed = 0.0
		if not Input.is_key_pressed(KEY_SPACE):
			player.remove_meta("tutorial_skip_hold")
	skip_progress.value = skip_elapsed
	if not visible_task:
		return
	if completed:
		progress += delta
		while completed and progress >= COMPLETION_DELAY:
			progress -= COMPLETION_DELAY
			step += 1
			completed = false
			_sync_jump_step_meta()
			if not pending_actions.is_empty():
				pending_actions.pop_front()
				completed = true
			else:
				progress = 0.0
			_update_text()
	panel.visible = visible_task and step < ACTIONS.size()

func _update_text() -> void:
	if step < TASKS.size():
		label.text = "ОБУЧЕНИЕ · %d / %d\n" % [step + 1, ACTIONS.size()] + ("✓ " if completed else "□ ") + TASKS[step]
