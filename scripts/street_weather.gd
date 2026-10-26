extends Node
## Session-local weather state. Only the street owns these resources.
signal weather_changed(mode: int)
signal time_of_day_changed(period: int)
enum Weather { SUNNY, EVENING, OVERCAST, STORM }
enum TimeOfDay { DAY, EVENING, NIGHT }
const PRESETS = [preload("res://shaders/presets/sunny.tres"), preload("res://shaders/presets/evening.tres"), preload("res://shaders/presets/overcast.tres"), preload("res://shaders/presets/storm.tres")]
const NIGHT_PRESET = preload("res://shaders/presets/night.tres")
const WEATHER_AUDIO = preload("res://scripts/weather_audio.gd")
const BLEND_DURATION := 1.5
@export var street: Node3D
@export var transition: Node
var mode: int = Weather.SUNNY
var time_of_day: int = TimeOfDay.DAY
var artificial_light_strength := 0.0
var in_street := false
var environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var wet_materials: Array[ShaderMaterial] = []
var rain: CPUParticles3D
var rain_material: ShaderMaterial
var rain_sound: AudioStreamPlayer
var thunder_sound: AudioStreamPlayer
var flash_light: DirectionalLight3D
var rain_strength := 0.0
var blend: Tween
var flash: Tween
var flash_remaining := 7.0
var thunder_remaining := -1.0
var rng := RandomNumberGenerator.new()
var rain_points := PackedVector3Array()
var last_rain_center := Vector2(INF, INF)

func _ready() -> void:
	rng.randomize()
	sun = street.get_node("Sun")
	environment = transition.destination_environment.duplicate(true)
	var sky := Sky.new()
	sky_material = preload("res://shaders/materials/street_sky.tres").duplicate()
	sky_material.set_shader_parameter("night_amount", 0.0)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.fog_enabled = true
	transition.destination_environment = environment
	transition.location_changed.connect(set_in_street)
	street.get_node("Clouds").hide() # The sky shader supplies weather-dependent clouds.
	_build_wet_surfaces()
	_build_audio()
	_build_lightning()
	_apply_preset(_current_preset(), false)
	if transition.in_city:
		player_camera().environment = environment
	set_in_street(transition.in_city)
	# Physics needs one completed frame before roof exclusion queries are reliable.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_build_rain()

func set_weather(next_mode: int) -> bool:
	if next_mode < 0 or next_mode >= PRESETS.size():
		return false
	if next_mode == mode:
		return true
	var next_time := time_of_day
	if next_mode == Weather.EVENING:
		next_time = TimeOfDay.EVENING
	elif mode == Weather.EVENING:
		next_time = TimeOfDay.DAY
	mode = next_mode
	if next_time != time_of_day:
		time_of_day = next_time
		time_of_day_changed.emit(time_of_day)
	_cancel_storm()
	_apply_preset(_current_preset(), true)
	weather_changed.emit(mode)
	return true

func set_time_of_day(next_period: int) -> bool:
	if next_period < TimeOfDay.DAY or next_period > TimeOfDay.NIGHT:
		return false
	if next_period == time_of_day:
		return true
	time_of_day = next_period
	if mode == Weather.EVENING and next_period != TimeOfDay.EVENING:
		mode = Weather.SUNNY
		weather_changed.emit(mode)
	_apply_preset(_current_preset(), true)
	time_of_day_changed.emit(time_of_day)
	return true

func _current_preset() -> Resource:
	var preset: Resource = PRESETS[mode].duplicate()
	var keys := ["top_color", "horizon_color", "cloud_color", "sun_color", "sun_energy", "sun_rotation", "ambient_color", "ambient_energy", "fog_color"]
	if time_of_day == TimeOfDay.NIGHT:
		for key in keys:
			preset.set(key, NIGHT_PRESET.get(key))
	elif time_of_day == TimeOfDay.EVENING and mode != Weather.STORM:
		for key in keys:
			preset.set(key, PRESETS[Weather.EVENING].get(key))
	return preset

func set_in_street(active: bool) -> void:
	in_street = active
	_cancel_storm()
	# Render layers alone do not deactivate a directional light or its shadows.
	# Keep the entire outdoor scene out of interior views, including the console.
	street.visible = active
	sun.visible = active
	flash_light.visible = active
	if street.has_method("set_city_active"):
		street.call("set_city_active", active)
	if not active:
		mode = Weather.SUNNY
		time_of_day = TimeOfDay.DAY
		_apply_preset(_current_preset(), false)
		weather_changed.emit(mode)
		time_of_day_changed.emit(time_of_day)
	if rain != null:
		rain.visible = active
		rain.emitting = active and rain_strength > 0.001
	_update_audio()

func player_camera() -> Camera3D:
	return transition.player.get_node("CameraPivot/Camera3D") as Camera3D

func _apply_preset(preset: Resource, animate: bool) -> void:
	if blend != null:
		blend.kill()
	blend = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var duration := BLEND_DURATION if animate else 0.0
	var night_amount := 1.0 if time_of_day == TimeOfDay.NIGHT else 0.0
	var lamps := 1.0 if time_of_day == TimeOfDay.NIGHT or mode == Weather.STORM else (0.65 if time_of_day == TimeOfDay.EVENING else 0.0)
	blend.tween_property(sky_material, "shader_parameter/night_amount", night_amount, duration)
	blend.tween_property(self, "artificial_light_strength", lamps, duration)
	for key in ["top_color", "horizon_color", "cloud_color", "cloud_cover", "sun_color"]:
		if not animate:
			sky_material.set_shader_parameter(key, preset.get(key))
		else:
			blend.tween_property(sky_material, "shader_parameter/" + key, preset.get(key), duration)
	if not animate:
		sky_material.set_shader_parameter("lightning", 0.0)
	blend.tween_property(sun, "light_color", preset.sun_color, duration)
	blend.tween_property(sun, "light_energy", preset.sun_energy, duration)
	blend.tween_property(sun, "rotation_degrees", preset.sun_rotation, duration)
	blend.tween_property(environment, "ambient_light_color", preset.ambient_color, duration)
	blend.tween_property(environment, "ambient_light_energy", preset.ambient_energy, duration)
	blend.tween_property(environment, "fog_light_color", preset.fog_color, duration)
	blend.tween_property(environment, "fog_density", preset.fog_density, duration)
	blend.tween_property(environment, "fog_height", preset.fog_height, duration)
	blend.tween_property(environment, "fog_height_density", preset.fog_height_density, duration)
	blend.tween_property(self, "rain_strength", preset.rain, duration)
	for material in wet_materials:
		blend.tween_property(material, "shader_parameter/wetness", preset.rain, duration)
	if not animate:
		blend.custom_step(0.0)

func _process(delta: float) -> void:
	sky_material.set_shader_parameter("sun_direction", sun.global_basis.z)
	if street.has_method("set_night_lighting"):
		street.call("set_night_lighting", artificial_light_strength if in_street else 0.0)
	if rain != null:
		if in_street:
			_update_rain_coverage()
		rain.visible = in_street and rain_strength > 0.001
		rain.emitting = rain.visible
		rain_material.set_shader_parameter("intensity", rain_strength)
	_update_audio()
	if not in_street or mode != Weather.STORM or rain_strength < 0.5:
		return
	if thunder_remaining >= 0.0:
		thunder_remaining -= delta
		if thunder_remaining < 0.0:
			thunder_sound.pitch_scale = rng.randf_range(0.85, 1.1)
			thunder_sound.play()
	flash_remaining -= delta
	if flash_remaining <= 0.0:
		_lightning_strike()

func _lightning_strike() -> void:
	if not in_street or mode != Weather.STORM:
		return
	flash_remaining = rng.randf_range(7.0, 14.0)
	thunder_remaining = rng.randf_range(0.8, 2.4)
	flash_light.rotation_degrees = Vector3(-55, rng.randf_range(-180, 180), 0)
	if flash != null:
		flash.kill()
	flash_light.light_energy = 2.5
	sky_material.set_shader_parameter("lightning", 0.65)
	flash = create_tween().set_parallel(true)
	flash.tween_property(flash_light, "light_energy", 0.0, 0.22)
	flash.tween_property(sky_material, "shader_parameter/lightning", 0.0, 0.22)

func _cancel_storm() -> void:
	thunder_remaining = -1.0
	flash_remaining = rng.randf_range(5.0, 10.0)
	if flash != null:
		flash.kill()
	flash_light.light_energy = 0.0
	sky_material.set_shader_parameter("lightning", 0.0)
	thunder_sound.stop()

func _update_audio() -> void:
	var audible := in_street and rain_strength > 0.001
	if audible:
		rain_sound.volume_db = linear_to_db(rain_strength * (0.35 / 3.0))
		if not rain_sound.playing:
			rain_sound.play()
	else:
		rain_sound.stop()

func _build_lightning() -> void:
	flash_light = DirectionalLight3D.new()
	flash_light.name = "Lightning"
	flash_light.light_color = Color(0.72, 0.82, 1.0)
	flash_light.light_energy = 0.0
	flash_light.light_cull_mask = 2
	flash_light.layers = 2
	flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	street.add_child(flash_light)

func _build_wet_surfaces() -> void:
	for mesh: MeshInstance3D in street.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_in_group("weather_wet_surface"):
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			if surface == int(mesh.get_meta("city_window_surface", -1)):
				continue
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/wet_surface.gdshader")
			material.set_shader_parameter("base_color", original.albedo_color)
			material.set_shader_parameter("use_base_texture", original.albedo_texture != null)
			if original.albedo_texture != null:
				material.set_shader_parameter("base_texture", original.albedo_texture)
			material.set_shader_parameter("dry_roughness", original.roughness)
			material.set_shader_parameter("wetness", 0.0)
			material.set_shader_parameter("ripple_noise", preload("res://shaders/textures/weather_noise.tres"))
			mesh.set_surface_override_material(surface, material)
			wet_materials.append(material)
		mesh.material_override = null

func _build_rain() -> void:
	# Sample each entire emission cell: no points are allowed above roofs, trees or gate.
	var space := street.get_world_3d().direct_space_state
	var bounds: Rect2 = street.get_meta("rain_bounds", Rect2(-24, -48, 48, 64))
	for x in range(int(bounds.position.x) + 2, int(bounds.end.x) - 1, 2):
		for z in range(int(bounds.position.y) + 2, int(bounds.end.y) - 1, 2):
			var open := true
			for offset in [Vector2.ZERO, Vector2(-0.85, -0.85), Vector2(0.85, -0.85), Vector2(-0.85, 0.85), Vector2(0.85, 0.85)]:
				var point := street.to_global(Vector3(x + offset.x, 24, z + offset.y))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 25, 0), 1))
				if hit.is_empty() or hit.collider != street.get_node("Ground"):
					open = false
					break
			if open:
				# Fixed vertical trajectories cannot drift underneath a roof.
				for offset in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
					rain_points.append(Vector3(x + offset.x, 24, z + offset.y))
	rain = CPUParticles3D.new()
	rain.name = "StreetRain"
	rain.emitting = false
	rain.amount = 5500
	rain.lifetime = 1.18
	rain.preprocess = 1.0
	rain.local_coords = true
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	rain.emission_points = rain_points
	rain.direction = Vector3.DOWN
	rain.spread = 0.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 20.0
	rain.initial_velocity_max = 20.0
	rain.layers = 2
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.55, 0.018)
	rain_material = preload("res://shaders/materials/rain.tres").duplicate()
	mesh.material = rain_material
	rain.mesh = mesh
	street.add_child(rain)
	_update_rain_coverage(true)
	rain.visible = in_street

func _update_rain_coverage(force: bool = false) -> void:
	var active_camera := street.get_viewport().get_camera_3d()
	var position_: Vector3 = street.to_local(active_camera.global_position) if in_street and active_camera != null else street.get_node("Arrival").position
	var center := Vector2(position_.x, position_.z)
	if not force and last_rain_center.distance_squared_to(center) < 36.0:
		return
	last_rain_center = center
	var nearby := PackedVector3Array()
	for point in rain_points:
		if Vector2(point.x, point.z).distance_squared_to(center) < 28.0 * 28.0:
			nearby.append(point)
	rain.emission_points = nearby

func _build_audio() -> void:
	# Fixed seeds keep generated sounds reproducible and independent of weather timing.
	rain_sound = AudioStreamPlayer.new()
	rain_sound.name = "RainSound"
	rain_sound.stream = WEATHER_AUDIO.synthesize_sound(true)
	add_child(rain_sound)
	thunder_sound = AudioStreamPlayer.new()
	thunder_sound.name = "ThunderSound"
	thunder_sound.stream = WEATHER_AUDIO.synthesize_sound(false)
	thunder_sound.volume_db = -7.0
	add_child(thunder_sound)

func _exit_tree() -> void:
	if rain_sound != null:
		rain_sound.stop()
	if thunder_sound != null:
		thunder_sound.stop()
