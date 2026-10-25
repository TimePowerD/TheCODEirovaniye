extends CanvasLayer

@export var player: CharacterBody3D
@export var menu: CanvasLayer
const ACTIONS := [&"walk", &"jump", &"pickup", &"swap"]
const COMPLETION_DELAY := 1.2
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
	player.gameplay_action.connect(_on_action)
	restart()

func restart() -> void:
	player.tutorial_walk_distance = 0.0
	pending_actions.clear()
	step = 0
	completed = false
	progress = 0.0
	_update_text()

func skip() -> void:
	pending_actions.clear()
	completed = false
	progress = 0.0
	step = ACTIONS.size()
	panel.hide()

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
	var visible_task: bool = menu.game_started and not player.has_meta("developer_tools_open") and not player.has_meta("cutscene_active")
	panel.visible = visible_task and step < ACTIONS.size()
	if not visible_task:
		return
	if completed:
		progress += delta
		while completed and progress >= COMPLETION_DELAY:
			progress -= COMPLETION_DELAY
			step += 1
			completed = false
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
