extends "res://scripts/location_transition.gd"
## Sends the player into a short, one-time forest flashback upon entering room three.

const FLASHBACK_DURATION := 25.0
const PRELUDE_DURATION := 2.0
const PRELUDE_SPEED_MULTIPLIER := 0.16
const FLASHBACK_SPEED_MULTIPLIER := 0.5
const HEARTBEAT_STREAM: AudioStream = preload("res://assets/audio/final sounds/heartbeat.mp3_.mp3")
const FOREST_AMBIENCE_STREAM: AudioStreamOggVorbis = preload("res://assets/audio/final sounds/forest_birds.ogg")
const WEATHER_AUDIO = preload("res://scripts/weather_audio.gd")

@onready var forest_sun: DirectionalLight3D = city_room.get_node("ForestSun") as DirectionalLight3D

var flashback_started := false
var flashback_active := false
var flashback_sequence_active := false
var flashback_completed := false
var rain_particles: GPUParticles3D
var heartbeat_player: AudioStreamPlayer
var forest_ambience: AudioStreamPlayer
var forest_rain_sound: AudioStreamPlayer

func _ready() -> void:
	destination_environment = _make_night_environment(destination_environment)
	super._ready()
	location_changed.connect(_set_forest_active)
	var loop_stream := FOREST_AMBIENCE_STREAM.duplicate() as AudioStreamOggVorbis
	loop_stream.loop = true
	forest_ambience = AudioStreamPlayer.new()
	forest_ambience.name = "ForestBirdAmbience"
	forest_ambience.stream = loop_stream
	forest_ambience.volume_db = -16.0
	add_child(forest_ambience)
	forest_rain_sound = AudioStreamPlayer.new()
	forest_rain_sound.name = "ForestRainSound"
	forest_rain_sound.stream = WEATHER_AUDIO.synthesize_sound(true)
	forest_rain_sound.volume_db = linear_to_db(0.35 / 3.0)
	add_child(forest_rain_sound)
	_build_rain()
	_build_heartbeat_player()
	_set_forest_active(in_city)
	if in_city:
		(player.get_node("CameraPivot/Camera3D") as Camera3D).environment = destination_environment
		_enter_flashback_state()
		call_deferred("_run_restored_flashback")

func _physics_process(delta: float) -> void:
	if flashback_sequence_active or flashback_active or flashback_completed:
		return
	super._physics_process(delta)

func _process(_delta: float) -> void:
	if in_city and rain_particles != null and is_instance_valid(player):
		rain_particles.global_position = player.global_position + Vector3(0.0, 10.0, 0.0)

func _on_exit(body: Node3D, to_city: bool) -> void:
	if body != player or not to_city or flashback_started or flashback_sequence_active \
		or transitioning or player.swap_in_progress or player.has_meta("location_transition_active") \
		or player.has_meta("cutscene_active") or player.has_meta("developer_tools_open"):
		return
	flashback_started = true
	flashback_sequence_active = true
	await _pulse_and_slow()
	await super._on_exit(body, true)
	flashback_sequence_active = false
	if not is_inside_tree() or not in_city:
		player.flashback_speed_multiplier = 1.0
		return
	_enter_flashback_state()
	await get_tree().create_timer(FLASHBACK_DURATION).timeout
	if not is_inside_tree() or not in_city:
		return
	await _return_to_laboratory()

func _run_restored_flashback() -> void:
	await get_tree().create_timer(FLASHBACK_DURATION).timeout
	if is_inside_tree() and in_city:
		await _return_to_laboratory()

func _return_to_laboratory() -> void:
	flashback_sequence_active = true
	await _pulse_and_slow()
	var tutorial := get_node_or_null("../Tutorial")
	if tutorial != null and tutorial.has_method("seal_all_tutorial_doors"):
		tutorial.call("seal_all_tutorial_doors")
	await super._on_exit(player, false)
	if tutorial != null and tutorial.has_method("resume_after_forest_flashback"):
		tutorial.call("resume_after_forest_flashback")
	var menu := get_node_or_null("../MainMenu")
	if menu != null and menu.has_method("end_flashback_music"):
		menu.call("end_flashback_music")
	flashback_active = false
	flashback_sequence_active = false
	flashback_completed = true
	player.flashback_speed_multiplier = 1.0
	if tutorial != null and tutorial.has_method("set_flashback_objective"):
		tutorial.call("set_flashback_objective", "")
	$LaboratoryExit.set_deferred("monitoring", false)

func _pulse_and_slow() -> void:
	if in_city:
		_set_flashback_effect_enabled(false)
	else:
		var menu := get_node_or_null("../MainMenu")
		if menu != null and menu.has_method("begin_flashback_music"):
			menu.call("begin_flashback_music")
		call_deferred("_play_first_flashback_heartbeats")
	veil.show()
	fade_material.set_shader_parameter("darkness", 0.0)
	fade_material.set_shader_parameter("blur_amount", 0.0)
	var speed_tween := create_tween()
	speed_tween.tween_property(player, "flashback_speed_multiplier", PRELUDE_SPEED_MULTIPLIER, PRELUDE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var blur_tween := create_tween()
	blur_tween.tween_property(fade_material, "shader_parameter/blur_amount", 0.7, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	blur_tween.tween_property(fade_material, "shader_parameter/blur_amount", 0.2, 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	blur_tween.tween_property(fade_material, "shader_parameter/blur_amount", 1.0, 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await speed_tween.finished
	await blur_tween.finished

func _enter_flashback_state() -> void:
	flashback_active = true
	player.flashback_speed_multiplier = FLASHBACK_SPEED_MULTIPLIER
	var tutorial := get_node_or_null("../Tutorial")
	if tutorial != null and tutorial.has_method("set_flashback_objective"):
		tutorial.call("set_flashback_objective", "Мне нужно вернуться домой.")

func _set_forest_active(active: bool) -> void:
	city_room.visible = active
	forest_sun.visible = active
	if active:
		if not forest_ambience.playing:
			forest_ambience.play()
		if not forest_rain_sound.playing:
			forest_rain_sound.play()
	else:
		forest_ambience.stop()
		forest_rain_sound.stop()
	if active:
		var menu := get_node_or_null("../MainMenu")
		if menu != null and menu.has_method("begin_flashback_music"):
			menu.call("begin_flashback_music")
	var tutorial := get_node_or_null("../Tutorial")
	if tutorial != null and tutorial.has_method("set_flashback_subtitles_hidden"):
		tutorial.call("set_flashback_subtitles_hidden", active)
	if rain_particles != null:
		rain_particles.visible = active
		rain_particles.emitting = active
		if active and is_instance_valid(player):
			rain_particles.global_position = player.global_position + Vector3(0.0, 10.0, 0.0)
	if active:
		forest_sun.light_color = Color(0.32, 0.4, 0.62)
		forest_sun.light_energy = 1.0

func _build_heartbeat_player() -> void:
	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.name = "FlashbackHeartbeat"
	heartbeat_player.stream = HEARTBEAT_STREAM
	heartbeat_player.volume_db = -3.0
	heartbeat_player.max_polyphony = 3
	add_child(heartbeat_player)

func _play_first_flashback_heartbeats() -> void:
	for beat_index in range(3):
		if not is_inside_tree() or heartbeat_player == null:
			return
		heartbeat_player.play()
		if beat_index < 2:
			await get_tree().create_timer(1.5).timeout

func _build_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "ForestRain"
	rain_particles.amount = 1800
	rain_particles.lifetime = 1.35
	rain_particles.local_coords = true
	rain_particles.emitting = false
	rain_particles.visibility_aabb = AABB(Vector3(-16.0, -12.0, -16.0), Vector3(32.0, 36.0, 32.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(14.0, 1.0, 14.0)
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 2.0
	process_material.gravity = Vector3(0.0, -2.0, 0.0)
	process_material.initial_velocity_min = 17.0
	process_material.initial_velocity_max = 20.0
	rain_particles.process_material = process_material
	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(0.018, 0.42, 0.018)
	var rain_material := StandardMaterial3D.new()
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.albedo_color = Color(0.62, 0.77, 0.96, 0.72)
	rain_mesh.material = rain_material
	rain_particles.draw_pass_1 = rain_mesh
	city_room.add_child(rain_particles)

func _make_night_environment(source: Environment) -> Environment:
	if source == null:
		return source
	var night := source.duplicate(true) as Environment
	night.background_mode = Environment.BG_SKY
	night.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	night.ambient_light_color = Color(0.27, 0.32, 0.45)
	night.ambient_light_energy = 0.8
	night.fog_enabled = true
	night.fog_light_color = Color(0.025, 0.04, 0.07)
	night.fog_density = 0.055
	night.fog_height_density = 0.09
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.008, 0.016, 0.06)
	sky_material.sky_horizon_color = Color(0.045, 0.07, 0.13)
	sky_material.ground_bottom_color = Color(0.012, 0.018, 0.032)
	sky_material.ground_horizon_color = Color(0.035, 0.052, 0.09)
	sky.sky_material = sky_material
	night.sky = sky
	return night
