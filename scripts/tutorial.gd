extends CanvasLayer

@export var player: CharacterBody3D
@export var menu: CanvasLayer
const ACTIONS := [&"look", &"walk", &"sprint", &"jump", &"grab", &"rotate", &"release_grab", &"pickup", &"use", &"place", &"pickup", &"throw", &"select_swap", &"swap", &"pause_resume", &"checkpoint", &"location_enter", &"location_return", &"flashback_enter", &"flashback_return"]
const TASKS := [
	"Мышь — осмотритесь вокруг",
	"WASD — пройдите один метр",
	"Shift + WASD — пробегите один метр",
	"Пробел — прыгните",
	"Наведитесь на куб или другой физический объект и удерживайте ПКМ — захват",
	"Удерживая ПКМ, зажмите R. Выберите ось 1 / 2 / 3 или наведением и двигайте мышью — вращение",
	"Отпустите R и ПКМ — отпустите захваченный объект",
	"Наведитесь на жёлтый предмет рядом с вами и нажмите E — взять в руку",
	"Коротко нажмите E с предметом в руке — использовать",
	"Удерживайте E, наведитесь на пол до появления метки и отпустите E — разместить предмет",
	"Наведитесь на размещённый предмет и нажмите E — снова взять",
	"Q — бросьте предмет из руки",
	"ЛКМ по доступному объекту — выберите первый объект для обмена",
	"ЛКМ по другому объекту — выполните обмен; оба объекта должны быть видны",
	"Esc — откройте паузу, затем Esc или «Продолжить» — вернитесь в игру",
	"Esc → «Вернуться на точку сохранения» — проверьте возврат",
	"Развернитесь к «ВЫХОДУ», пройдите до конца коридора — переход в локацию",
	"Подойдите к двери «ВЫХОД» позади точки появления — вернитесь в лабораторию",
	"У левой стены лаборатории подойдите к «ЗНАКОМОЙ ДВЕРИ» — флэшбэк",
	"Через «ВЫХОД» комнаты воспоминания вернитесь в лабораторию",
]
var step := 0
var completed := false
var progress := 0.0
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
	player.tutorial_sprint_distance = 0.0
	player.tutorial_look_distance = 0.0
	step = 0
	completed = false
	progress = 0.0
	_update_text()

func skip() -> void:
	step = ACTIONS.size()
	panel.hide()

func _on_action(action: StringName) -> void:
	if step >= ACTIONS.size() or completed or action != ACTIONS[step]:
		return
	if player.has_meta("developer_tools_open") or player.has_meta("cutscene_active") or player.has_meta("location_transition_active"):
		return
	completed = true
	progress = 0.0
	_update_text()

func _process(delta: float) -> void:
	panel.visible = menu.game_started and step < ACTIONS.size() and not player.has_meta("developer_tools_open")
	if completed:
		progress += delta
		if progress >= 1.2:
			step += 1
			completed = false
			_update_text()

func _update_text() -> void:
	if step < TASKS.size():
		label.text = "ОБУЧЕНИЕ · %d / %d\n" % [step + 1, ACTIONS.size()] + ("✓ " if completed else "□ ") + TASKS[step]
