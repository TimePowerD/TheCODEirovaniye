extends "res://scripts/location_teleport_trigger.gd"

const COLD_GRADE_SHADER: Shader = preload("res://scripts/kitchen_cold_grade.gdshader")
const KATE_TYPING_SOUND: AudioStream = preload("res://assets/audio/audiointefsce/Audio/click3.ogg")
const KATE_LINES := ["Что?..", "Ты.. выжил?...", "Что ты делаешь?!"]
const KATE_IDLE_ANIMATION: StringName = &"mixamo_com_001"
const LINE_HOLD_SECONDS := 2.0
const END_CREDITS_DELAY: float = 5.0
const CHARACTER_INTERVAL := 0.045
const PERIOD_PAUSE := 0.3
const END_CREDITS_JOKE := "И помните: сколько зомби ни корми, всё равно съест жинку."

var kate_cutscene_played := false
var cutscene_storm_active := false
var storm_flash_remaining := 0.0
var storm_flash_light: OmniLight3D
var storm_flash_tween: Tween
var storm_rng := RandomNumberGenerator.new()
var kitchen_warm_light: AreaLight3D
var kitchen_warm_energy := 0.0
var restored_cutscene_pending := false


func _ready() -> void:
	super._ready()
	storm_rng.randomize()
	# Do not leave the kitchen arrival blurred for the laboratory's long default reveal.
	blur_clear_duration = minf(blur_clear_duration, 0.65)
	var kate := get_tree().current_scene.find_child("Kate", true, false) as Node3D
	if kate != null:
		kate.set_visible(false)
	var save_manager := get_node("/root/SaveManager")
	save_manager.checkpoint_restored.connect(_on_final_checkpoint_restored)
	if save_manager.current_location_id == "kitchen":
		call_deferred("_on_final_checkpoint_restored", "kitchen")


func _on_final_checkpoint_restored(location_id: String) -> void:
	# Normal door entry runs the scene after its fade. Loading its saved checkpoint
	# has no such coroutine, so resume it once the main menu releases the game.
	if location_id != "kitchen" or transitioning or kate_cutscene_played or restored_cutscene_pending:
		return
	restored_cutscene_pending = true
	call_deferred("_resume_final_cutscene")


func _resume_final_cutscene() -> void:
	var save_manager := get_node("/root/SaveManager")
	var menu := get_tree().current_scene.get_node("MainMenu")
	while get_tree().paused or not bool(menu.get("game_started")):
		await get_tree().process_frame
		if save_manager.current_location_id != "kitchen":
			restored_cutscene_pending = false
			return
	restored_cutscene_pending = false
	if save_manager.current_location_id != "kitchen" or transitioning or kate_cutscene_played:
		return
	var player := get_tree().current_scene.get_node("Player") as CharacterBody3D
	var was_physics_processing := player.is_physics_processing()
	var was_input_processing := player.is_processing_unhandled_input()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.velocity = Vector3.ZERO
	await _after_visual_transition_reveal(player)
	player.set_physics_process(was_physics_processing)
	player.set_process_unhandled_input(was_input_processing)


func _after_visual_transition_reveal(player: CharacterBody3D) -> void:
	if kate_cutscene_played:
		return

	var kate := get_tree().current_scene.find_child("Kate", true, false) as Node3D
	if kate == null:
		push_error("Kitchen flashback: the editor-placed Kate node was not found.")
		return

	kate_cutscene_played = true
	player.set_meta("cutscene_active", true)
	_start_cutscene_storm()
	kate.set_visible(true)
	_start_kate_idle(kate)

	var subtitle := _create_subtitles()
	var speaker: Label = subtitle.get_node("Panel/Content/Speaker")
	var line_label: Label = subtitle.get_node("Panel/Content/Line")
	var typing_sound: AudioStreamPlayer = subtitle.get_node("TypingSound")
	speaker.text = "Кейт"
	for line in KATE_LINES:
		await _type_kate_line(line_label, typing_sound, line)
		await get_tree().create_timer(LINE_HOLD_SECONDS).timeout
	subtitle.queue_free()

	await _flash_and_dismiss_kate(kate)
	_stop_cutscene_lightning()
	get_tree().create_timer(END_CREDITS_DELAY).timeout.connect(_show_end_credits)
	player.remove_meta("cutscene_active")


func _process(delta: float) -> void:
	if not cutscene_storm_active:
		return
	storm_flash_remaining -= delta
	if storm_flash_remaining <= 0.0:
		_flash_lightning()


func _start_cutscene_storm() -> void:
	var kitchen := get_tree().current_scene.find_child("KitchenRoom", true, false) as Node3D
	if kitchen == null:
		return
	var storm_audio := kitchen.get_node_or_null("LightningStormAudio") as AudioStreamPlayer
	if storm_audio != null:
		storm_audio.play()
	kitchen_warm_light = kitchen.get_node_or_null("WarmLight") as AreaLight3D
	if kitchen_warm_light != null:
		kitchen_warm_energy = kitchen_warm_light.light_energy
		create_tween().tween_property(kitchen_warm_light, "light_energy", kitchen_warm_energy * 0.35, 0.8)
	storm_flash_light = kitchen.get_node_or_null("CutsceneStormLightning") as OmniLight3D
	if storm_flash_light == null:
		storm_flash_light = OmniLight3D.new()
		storm_flash_light.name = "CutsceneStormLightning"
		storm_flash_light.position = Vector3(0.0, 2.4, 0.0)
		storm_flash_light.light_color = Color(0.68, 0.8, 1.0)
		storm_flash_light.light_energy = 0.0
		storm_flash_light.omni_range = 16.0
		storm_flash_light.omni_attenuation = 0.7
		kitchen.add_child(storm_flash_light)
	cutscene_storm_active = true
	storm_flash_remaining = 0.35


func _flash_lightning() -> void:
	if not is_instance_valid(storm_flash_light):
		return
	if storm_flash_tween != null:
		storm_flash_tween.kill()
	storm_flash_light.light_energy = storm_rng.randf_range(3.5, 5.5)
	storm_flash_tween = create_tween()
	storm_flash_tween.tween_property(storm_flash_light, "light_energy", 0.0, 0.16)
	storm_flash_remaining = storm_rng.randf_range(2.2, 5.5)


func _stop_cutscene_lightning() -> void:
	cutscene_storm_active = false
	if storm_flash_tween != null:
		storm_flash_tween.kill()
	if is_instance_valid(storm_flash_light):
		storm_flash_light.light_energy = 0.0
	if is_instance_valid(kitchen_warm_light):
		create_tween().tween_property(kitchen_warm_light, "light_energy", kitchen_warm_energy, 0.8)


func _show_end_credits() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EndCredits"
	layer.layer = 10
	get_tree().current_scene.add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.075, 0.09, 0.94)
	panel_style.border_color = Color(0.36, 0.47, 0.58, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(30)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	panel_style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	var title := Label.new()
	title.text = "Спасибо за игру"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.94, 0.96, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var joke := Label.new()
	joke.text = END_CREDITS_JOKE
	joke.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	joke.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joke.add_theme_font_size_override("font_size", 16)
	joke.add_theme_color_override("font_color", Color(0.65, 0.71, 0.74))
	joke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(joke)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 1.6)


func _type_kate_line(label: Label, typing_sound: AudioStreamPlayer, full_text: String) -> void:
	label.text = ""
	for index in full_text.length():
		var character := full_text.substr(index, 1)
		label.text += character
		if not character.strip_edges().is_empty():
			typing_sound.play()
		if index < full_text.length() - 1:
			var delay := PERIOD_PAUSE if character == "." else CHARACTER_INTERVAL
			await get_tree().create_timer(delay).timeout


func _start_kate_idle(kate: Node3D) -> void:
	var animation_players := kate.find_children("*", "AnimationPlayer", true, false)
	if animation_players.is_empty():
		return
	var animation_player := animation_players[0] as AnimationPlayer
	if not animation_player.has_animation(KATE_IDLE_ANIMATION):
		var animations := animation_player.get_animation_list()
		if animations.is_empty():
			return
		var fallback_name: StringName = animations[0]
		animation_player.play(fallback_name)
		return
	var animation := animation_player.get_animation(KATE_IDLE_ANIMATION)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	animation_player.play(KATE_IDLE_ANIMATION)


func _create_subtitles() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "KateSubtitles"
	layer.layer = 8
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -420.0
	panel.offset_right = 420.0
	panel.offset_top = -142.0
	panel.offset_bottom = -28.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.065, 0.9)
	style.border_color = Color(0.42, 0.66, 0.9, 0.72)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var typing_sound := AudioStreamPlayer.new()
	typing_sound.name = "TypingSound"
	typing_sound.stream = KATE_TYPING_SOUND
	typing_sound.volume_db = -18.0
	typing_sound.max_polyphony = 3
	layer.add_child(typing_sound)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var speaker := Label.new()
	speaker.name = "Speaker"
	speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker.add_theme_font_size_override("font_size", 14)
	speaker.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	content.add_child(speaker)
	var line := Label.new()
	line.name = "Line"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 22)
	line.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	content.add_child(line)
	return layer


func _flash_and_dismiss_kate(kate: Node3D) -> void:
	var flash_layer := CanvasLayer.new()
	flash_layer.name = "KateWhiteFlash"
	flash_layer.layer = 9
	add_child(flash_layer)
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 1.0, 0.08)
	tween.tween_interval(0.08)
	tween.tween_callback(kate.hide)
	tween.tween_callback(_apply_cold_grade)
	tween.tween_property(flash, "modulate:a", 0.0, 0.24)
	await tween.finished
	flash_layer.queue_free()


func _apply_cold_grade() -> void:
	var grade_layer := CanvasLayer.new()
	grade_layer.name = "KitchenColdGrade"
	grade_layer.layer = 3
	add_child(grade_layer)
	var screen_grade := ColorRect.new()
	screen_grade.name = "ColdColorGrade"
	screen_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = COLD_GRADE_SHADER
	material.set_shader_parameter("amount", 1.0)
	screen_grade.material = material
	grade_layer.add_child(screen_grade)
