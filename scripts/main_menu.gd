extends CanvasLayer

@onready var click_sound: AudioStreamPlayer = $ClickSound

const PANEL_COLOR := Color(0.055, 0.075, 0.075, 0.96)
const ACCENT_COLOR := Color(0.72, 0.86, 0.52)
const MUTED_COLOR := Color(0.65, 0.71, 0.68)

var menu_root: Control
var content: VBoxContainer
var status_label: Label
var game_started: bool = false
var settings_return_to_pause: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	call_deferred("_show_menu_cursor")
	_build_interface()

func _show_menu_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_interface() -> void:
	menu_root = Control.new()
	menu_root.name = "MenuRoot"
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.027, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.add_theme_constant_override("margin_left", 36)
	content.add_theme_constant_override("margin_right", 36)
	content.add_theme_constant_override("margin_top", 32)
	content.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(content)
	_show_main_menu()

func _input(event: InputEvent) -> void:
	if not game_started or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			_resume_game()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()

func start_test_session() -> void:
	game_started = true
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _show_main_menu() -> void:
	_clear_content()
	_add_eyebrow("ПРОЕКТ «ЗАКОДИРОВАННЫЕ»")
	_add_title("ПОСЛЕДНИЙ\nПЕРЕЗАПУСК")
	_add_label("Похоже, этот мир снова нуждается в паре правок.", MUTED_COLOR, 15)
	_add_spacer(12)
	_add_button("Играть", _on_play_pressed, true)
	_add_button("Настройки", _show_settings)
	_add_button("Разработчики", _show_developers)
	_add_button("Выйти", _on_quit_pressed)
	_add_spacer(4)
	_add_label("Нажмите «Играть», когда будете готовы проснуться.", MUTED_COLOR, 12)

func _show_settings() -> void:
	_clear_content()
	_add_eyebrow("ПАРАМЕТРЫ")
	_add_title("Настройки")
	_add_label("Язык интерфейса", MUTED_COLOR, 14)
	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 10)
	content.add_child(language_row)
	var russian := _make_button("Русский", func(): _set_language("Русский"), true)
	var english := _make_button("English", func(): _set_language("English"))
	language_row.add_child(russian)
	language_row.add_child(english)
	status_label = _add_label("Выбор языка пока демонстрационный.", MUTED_COLOR, 12)
	_add_label("Звук и графика появятся здесь позже.", MUTED_COLOR, 12)
	_add_spacer(10)
	_add_button("Назад", _show_pause_menu if settings_return_to_pause else _show_main_menu)

func _show_pause_menu() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_root.show()
	menu_root.modulate.a = 1.0
	settings_return_to_pause = true
	_clear_content()
	_add_eyebrow("ПАУЗА")
	_add_title("Игра приостановлена")
	_add_button("Продолжить", _resume_game, true)
	_add_button("Настройки", _show_pause_settings)
	_add_button("Вернуться на точку сохранения", _return_to_checkpoint)
	_add_button("Выйти в главное меню", _return_to_main_menu)

func _show_pause_settings() -> void:
	settings_return_to_pause = true
	_show_settings()

func _resume_game() -> void:
	game_started = true
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _return_to_checkpoint() -> void:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null and player.has_method("return_to_checkpoint"):
		player.return_to_checkpoint()
	_resume_game()

func _return_to_main_menu() -> void:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null and player.has_method("return_to_checkpoint"):
		player.return_to_checkpoint()
	game_started = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_root.show()
	menu_root.modulate.a = 1.0
	settings_return_to_pause = false
	_show_main_menu()

func _show_developers() -> void:
	_clear_content()
	_add_eyebrow("О СОЗДАТЕЛЯХ")
	_add_title("Разработчики")
	_add_label("Команда «Закодированные»", ACCENT_COLOR, 17)
	_add_label("Мы настолько закодировались, что даже зомби встаёт по нашему дедлайну. Если что-то пошло не так — это не баг, а сюжетный поворот.", MUTED_COLOR, 15)
	_add_spacer(14)
	_add_button("Назад", _show_main_menu)

func _on_play_pressed() -> void:
	var tween := create_tween()
	tween.tween_property(menu_root, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_start_game)

func _start_game() -> void:
	game_started = true
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_quit_pressed() -> void:
	get_tree().quit()

func _set_language(language: String) -> void:
	if status_label != null:
		status_label.text = "Язык: %s (пока заглушка)" % language

func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()
	status_label = null

func _add_eyebrow(text: String) -> void:
	_add_label(text, ACCENT_COLOR, 11)

func _add_title(text: String) -> void:
	var label := _add_label(text, Color(0.94, 0.96, 0.9), 30)
	label.add_theme_font_size_override("font_size", 30)

func _add_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	content.add_child(label)
	return label

func _add_spacer(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	content.add_child(spacer)

func _add_button(text: String, callback: Callable, primary: bool = false) -> void:
	content.add_child(_make_button(text, callback, primary))

func _make_button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color(0.94, 0.96, 0.9))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(primary, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true))
	button.add_theme_stylebox_override("focus", _button_style(primary, false))
	button.pressed.connect(func(): click_sound.play())
	button.pressed.connect(callback)
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.36, 0.47, 0.37, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(32)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 24
	return style

func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = ACCENT_COLOR.lightened(0.08) if hovered else ACCENT_COLOR
		style.border_color = ACCENT_COLOR
	else:
		style.bg_color = Color(0.11, 0.15, 0.14, 0.95) if hovered else Color(0.08, 0.11, 0.11, 0.8)
		style.border_color = Color(0.27, 0.34, 0.3, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
