extends CanvasLayer

@onready var click_sound: AudioStreamPlayer = $ClickSound

const MENU_MUSIC_STREAM: AudioStream = preload("res://assets/audio/final sounds/Zombie's Lullaby.mp3")
const GAME_MUSIC_STREAM: AudioStream = preload("res://assets/audio/final sounds/Isolated Space.mp3")

const PANEL_COLOR := Color(0.055, 0.075, 0.075, 0.96)
const ACCENT_COLOR := Color(0.72, 0.86, 0.52)
const MUTED_COLOR := Color(0.65, 0.71, 0.68)
const CLICK_AUDIO_BUS := "MenuClickFiltered"
const MUSIC_AUDIO_BUS := "Music"
const SFX_AUDIO_BUS := "SFX"
const FOOTSTEP_AUDIO_BUS := "FootstepsFiltered"
const JUMP_AUDIO_BUS := "JumpFiltered"
const SETTINGS_PATH := "user://audio_settings.cfg"
const GAME_MUSIC_VOLUME_DB := -24.0
const MENU_MUSIC_VOLUME_DB := -12.0
const GAME_LOOP_CROSSFADE := 1.0

var menu_root: Control
var content: VBoxContainer
var status_label: Label
var game_started: bool = false
var settings_return_to_pause: bool = false
var starting_game: bool = false
var start_with_cutscene := true
var menu_music_player: AudioStreamPlayer
var game_music_players: Array[AudioStreamPlayer] = []
var current_game_music_player: AudioStreamPlayer
var game_music_crossfade_tween: Tween
var music_transition_tween: Tween
var music_transition_id: int = 0
var game_music_crossfading: bool = false
var music_volume_percent: float = 100.0
var sfx_volume_percent: float = 100.0
var _game_music_next_player: AudioStreamPlayer
var _game_music_old_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_audio_settings()
	_configure_audio_buses()
	_route_existing_audio_players(get_tree().root)
	get_tree().node_added.connect(_route_audio_player)
	_configure_click_sound()
	_setup_music_players()
	get_tree().paused = true
	call_deferred("_show_menu_cursor")
	_build_interface()

func _configure_click_sound() -> void:
	var bus_index := AudioServer.get_bus_index(CLICK_AUDIO_BUS)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, CLICK_AUDIO_BUS)
		AudioServer.set_bus_send(bus_index, SFX_AUDIO_BUS)
	var low_pass: AudioEffectLowPassFilter
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectLowPassFilter:
			low_pass = effect
			break
	if low_pass == null:
		low_pass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(bus_index, low_pass)
	low_pass.cutoff_hz = 3200.0
	click_sound.bus = CLICK_AUDIO_BUS
	click_sound.volume_db = -8.0
	click_sound.pitch_scale = 1.05
	_apply_audio_volumes()

func _configure_audio_buses() -> void:
	_ensure_audio_bus(SFX_AUDIO_BUS, "Master")
	_ensure_audio_bus(MUSIC_AUDIO_BUS, "Master")
	_ensure_audio_bus(CLICK_AUDIO_BUS, SFX_AUDIO_BUS)
	_ensure_audio_bus(FOOTSTEP_AUDIO_BUS, SFX_AUDIO_BUS)
	_ensure_audio_bus(JUMP_AUDIO_BUS, SFX_AUDIO_BUS)
	var click_bus_index := AudioServer.get_bus_index(CLICK_AUDIO_BUS)
	var footstep_bus_index := AudioServer.get_bus_index(FOOTSTEP_AUDIO_BUS)
	var jump_bus_index := AudioServer.get_bus_index(JUMP_AUDIO_BUS)
	_configure_low_pass_bus(click_bus_index, 3200.0)
	_configure_low_pass_bus(footstep_bus_index, 3000.0)
	_configure_low_pass_bus(jump_bus_index, 4500.0)

func _ensure_audio_bus(bus_name: String, send_to: String) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, send_to)
	return bus_index

func _configure_low_pass_bus(bus_index: int, cutoff_hz: float) -> void:
	var low_pass: AudioEffectLowPassFilter
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectLowPassFilter:
			low_pass = effect
			break
	if low_pass == null:
		low_pass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(bus_index, low_pass)
	low_pass.cutoff_hz = cutoff_hz

func _route_existing_audio_players(node: Node) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D or child is AudioStreamPlayer3D:
			_route_audio_player(child)
		_route_existing_audio_players(child)

func _route_audio_player(node: Node) -> void:
	if not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		return
	if node.has_meta("audio_category") and node.get_meta("audio_category") == "music":
		node.bus = MUSIC_AUDIO_BUS
	elif node == click_sound:
		node.bus = CLICK_AUDIO_BUS
	elif node.name == "FootstepSound":
		node.bus = FOOTSTEP_AUDIO_BUS
	elif node.name == "JumpSound":
		node.bus = JUMP_AUDIO_BUS
	else:
		node.bus = SFX_AUDIO_BUS

func _load_audio_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		music_volume_percent = clampf(float(settings.get_value("audio", "music", 100.0)), 0.0, 100.0)
		sfx_volume_percent = clampf(float(settings.get_value("audio", "sfx", 100.0)), 0.0, 100.0)

func _save_audio_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "music", music_volume_percent)
	settings.set_value("audio", "sfx", sfx_volume_percent)
	settings.save(SETTINGS_PATH)

func _apply_audio_volumes() -> void:
	var music_bus_index := AudioServer.get_bus_index(MUSIC_AUDIO_BUS)
	var sfx_bus_index := AudioServer.get_bus_index(SFX_AUDIO_BUS)
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, _percent_to_db(music_volume_percent))
	if sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_index, _percent_to_db(sfx_volume_percent))

func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)

func _setup_music_players() -> void:
	menu_music_player = _create_music_player("MenuMusic", MENU_MUSIC_STREAM)
	menu_music_player.stream = _duplicate_stream_with_loop(MENU_MUSIC_STREAM, true)
	game_music_players.append(_create_music_player("GameMusicA", _duplicate_stream_with_loop(GAME_MUSIC_STREAM, false)))
	game_music_players.append(_create_music_player("GameMusicB", _duplicate_stream_with_loop(GAME_MUSIC_STREAM, false)))
	menu_music_player.volume_db = -80.0
	for player in game_music_players:
		player.volume_db = -80.0
	_switch_music_mode(false)

func _create_music_player(player_name: String, audio_stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.set_meta("audio_category", "music")
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = MUSIC_AUDIO_BUS
	player.stream = audio_stream
	add_child(player)
	return player

func _duplicate_stream_with_loop(audio_stream: AudioStream, should_loop: bool) -> AudioStream:
	var stream_copy := audio_stream.duplicate() as AudioStream
	if stream_copy is AudioStreamMP3:
		stream_copy.loop = should_loop
	return stream_copy

func _switch_music_mode(use_game_music: bool) -> void:
	music_transition_id += 1
	var transition_id := music_transition_id
	if music_transition_tween != null and music_transition_tween.is_running():
		music_transition_tween.kill()
	if game_music_crossfade_tween != null and game_music_crossfade_tween.is_running():
		game_music_crossfade_tween.kill()
	game_music_crossfading = false
	var outgoing_players: Array[AudioStreamPlayer] = []
	if menu_music_player != null and menu_music_player.playing:
		outgoing_players.append(menu_music_player)
	for player in game_music_players:
		if player.playing:
			outgoing_players.append(player)
	if not outgoing_players.is_empty():
		music_transition_tween = create_tween()
		music_transition_tween.set_parallel(true)
		for player in outgoing_players:
			music_transition_tween.tween_property(player, "volume_db", -80.0, 0.35)
		await get_tree().create_timer(0.36, true, false, true).timeout
		if transition_id != music_transition_id:
			return
		for player in outgoing_players:
			player.stop()
	current_game_music_player = null
	await get_tree().create_timer(0.5, true, false, true).timeout
	if transition_id != music_transition_id:
		return
	if use_game_music:
		_start_game_music()
	else:
		menu_music_player.volume_db = -80.0
		menu_music_player.play()
		music_transition_tween = create_tween()
		music_transition_tween.tween_property(menu_music_player, "volume_db", MENU_MUSIC_VOLUME_DB, 0.7)

func _start_game_music() -> void:
	current_game_music_player = game_music_players[0]
	current_game_music_player.volume_db = -80.0
	current_game_music_player.play()
	var fade_in := create_tween()
	fade_in.tween_property(current_game_music_player, "volume_db", GAME_MUSIC_VOLUME_DB, 0.7)

func _process(_delta: float) -> void:
	if game_started and not get_tree().paused and current_game_music_player != null and not game_music_crossfading:
		var duration := current_game_music_player.stream.get_length()
		if duration > GAME_LOOP_CROSSFADE and current_game_music_player.get_playback_position() >= duration - GAME_LOOP_CROSSFADE:
			_begin_game_music_crossfade()

func _begin_game_music_crossfade() -> void:
	game_music_crossfading = true
	_game_music_old_player = current_game_music_player
	for player in game_music_players:
		if player != _game_music_old_player:
			_game_music_next_player = player
			break
	_game_music_next_player.volume_db = -80.0
	_game_music_next_player.play()
	game_music_crossfade_tween = create_tween()
	game_music_crossfade_tween.tween_method(_set_game_music_crossfade, 0.0, 1.0, GAME_LOOP_CROSSFADE)
	game_music_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	game_music_crossfade_tween.finished.connect(_finish_game_music_crossfade)

func _set_game_music_crossfade(progress: float) -> void:
	_game_music_old_player.volume_db = GAME_MUSIC_VOLUME_DB + _percent_to_db((1.0 - progress) * 100.0)
	_game_music_next_player.volume_db = GAME_MUSIC_VOLUME_DB + _percent_to_db(progress * 100.0)

func _finish_game_music_crossfade() -> void:
	_game_music_old_player.stop()
	_game_music_old_player.volume_db = -80.0
	_game_music_next_player.volume_db = GAME_MUSIC_VOLUME_DB
	current_game_music_player = _game_music_next_player
	game_music_crossfading = false

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
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null and player.has_meta("developer_tools_open"):
		return
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
	_switch_music_mode(true)
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_start_wake_cutscene()

func _show_main_menu() -> void:
	_clear_content()
	_add_eyebrow("ПРОЕКТ «ЗАКОДИРОВАННЫЕ»")
	_add_title("ПОСЛЕДНИЙ\nПЕРЕЗАПУСК")
	_add_label("Похоже, этот мир снова нуждается в паре правок.", MUTED_COLOR, 15)
	_add_spacer(12)
	_add_button("Новая игра", _on_new_game_pressed, true)
	var continue_button := _add_button("Продолжить", _on_continue_pressed)
	continue_button.disabled = not get_node("/root/SaveManager").has_valid_checkpoint()
	if continue_button.disabled:
		continue_button.modulate = Color(0.55, 0.58, 0.55, 0.62)
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
	_add_label("Громкость музыки", MUTED_COLOR, 14)
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 100.0
	music_slider.step = 1.0
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.value = music_volume_percent
	music_slider.value_changed.connect(_on_music_volume_changed)
	content.add_child(music_slider)
	_add_label("Громкость звуков", MUTED_COLOR, 14)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 100.0
	sfx_slider.step = 1.0
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value = sfx_volume_percent
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	content.add_child(sfx_slider)
	_add_spacer(10)
	_add_button("Назад", _show_pause_menu if settings_return_to_pause else _show_main_menu)

func _on_music_volume_changed(value: float) -> void:
	music_volume_percent = value
	_apply_audio_volumes()
	_save_audio_settings()

func _on_sfx_volume_changed(value: float) -> void:
	sfx_volume_percent = value
	_apply_audio_volumes()
	_save_audio_settings()

func _show_pause_menu() -> void:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null:
		player.reset_interaction_modes()
	_switch_music_mode(false)
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
	var checkpoint_button := _add_button("Вернуться на точку сохранения", _return_to_checkpoint)
	checkpoint_button.disabled = player != null and (player.has_meta("location_transition_active") or player.has_meta("cutscene_active"))
	_add_button("Выйти в главное меню", _return_to_main_menu)

func _show_pause_settings() -> void:
	settings_return_to_pause = true
	_show_settings()

func _resume_game() -> void:
	var resumed_from_pause := get_tree().paused and game_started
	var player := get_tree().current_scene.find_child("Player", true, false)
	if resumed_from_pause and player != null:
		player.reset_interaction_modes()
	game_started = true
	_switch_music_mode(true)
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if resumed_from_pause:
		if player != null:
			player.gameplay_action.emit(&"pause_resume")

func _return_to_checkpoint() -> void:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null and (player.has_meta("location_transition_active") or player.has_meta("cutscene_active")):
		return
	if player != null and player.has_method("return_to_checkpoint"):
		player.return_to_checkpoint()
	_resume_game()

func _return_to_main_menu() -> void:
	# Recreate scene state too: overlays, route state, items and checkpoints.
	get_tree().reload_current_scene()

func _show_developers() -> void:
	_clear_content()
	_add_eyebrow("О СОЗДАТЕЛЯХ")
	_add_title("Разработчики")
	_add_label("Команда «Закодированные»", ACCENT_COLOR, 17)
	_add_label("Мы настолько закодировались, что даже зомби встаёт по нашему дедлайну. Если что-то пошло не так — это не баг, а сюжетный поворот.", MUTED_COLOR, 15)
	_add_spacer(14)
	_add_button("Назад", _show_main_menu)

func _on_play_pressed() -> void:
	_on_new_game_pressed()

func _on_new_game_pressed() -> void:
	if starting_game:
		return
	var player := get_tree().current_scene.find_child("Player", true, false) as CharacterBody3D
	if player != null:
		get_node("/root/SaveManager").start_new_game(player)
		var tutorial := get_tree().current_scene.find_child("Tutorial", true, false)
		if tutorial != null and tutorial.has_method("restart"):
			tutorial.restart()
	start_with_cutscene = true
	_begin_game_start()

func _on_continue_pressed() -> void:
	if starting_game or not get_node("/root/SaveManager").has_valid_checkpoint():
		return
	var player := get_tree().current_scene.find_child("Player", true, false) as CharacterBody3D
	if player == null or not get_node("/root/SaveManager").restore_player(player):
		return
	var tutorial := get_tree().current_scene.find_child("Tutorial", true, false)
	if tutorial != null and tutorial.has_method("complete"):
		tutorial.complete()
	start_with_cutscene = false
	_begin_game_start()

func _begin_game_start() -> void:
	starting_game = true
	var tween := create_tween()
	tween.tween_property(menu_root, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_start_game)

func _start_game() -> void:
	starting_game = false
	game_started = true
	_switch_music_mode(true)
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if start_with_cutscene:
		_start_wake_cutscene()

func _start_wake_cutscene() -> void:
	var cutscene := get_tree().current_scene.find_child("WakeCutscene", true, false)
	if cutscene != null and cutscene.has_method("play"):
		cutscene.call_deferred("play")

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

func _add_button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := _make_button(text, callback, primary)
	content.add_child(button)
	return button

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
