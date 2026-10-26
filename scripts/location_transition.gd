extends Node

signal location_changed(in_destination: bool)

const TRANSITION_STREAM: AudioStream = preload("res://assets/audio/final sounds/location_teleport.mp3")

## A slow blackout links the laboratory to an apparently remembered city room.
@export var city_room: Node3D
@export var player: CharacterBody3D
@export var laboratory_light: Light3D
@export var destination_environment: Environment
@export var source_location_id := "laboratory"
@export var destination_location_id := "city"
var transition_style: int = 0
@export_range(0.1, 5.0, 0.05) var fade_out_duration: float = 1.2
@export_range(0.0, 3.0, 0.05) var black_hold_duration: float = 0.65
@export_range(0.1, 5.0, 0.05) var fade_in_duration: float = 2.0
@export_range(0.1, 10.0, 0.05) var blur_clear_duration: float = 3.0

var transitioning := false
var in_city := false
var veil: ColorRect
var fade_material: ShaderMaterial
var ambience: AudioStreamPlayer
var transition_sound: AudioStreamPlayer
var laboratory_energy: float
var laboratory_dimmed := false
var source_environment: Environment
var laboratory_environment: Environment
var flashback_effect: Node

func _ready() -> void:
	transition_style = $LaboratoryExit.transition_style
	flashback_effect = get_node_or_null("../FlashbackDerealization")
	laboratory_environment = player.get_node("CameraPivot/Camera3D").environment
	in_city = get_node("/root/SaveManager").current_location_id == destination_location_id
	get_node("/root/SaveManager").checkpoint_restored.connect(_on_checkpoint_restored)
	# Older street checkpoints used the small scene's previous world position.
	if in_city and city_room.has_meta("rain_bounds"):
		var bounds: Rect2 = city_room.get_meta("rain_bounds")
		var local_position := city_room.to_local(player.global_position)
		if not bounds.has_point(Vector2(local_position.x, local_position.z)):
			player.global_transform = city_room.get_node("Arrival").global_transform
			player.checkpoint_transform = player.global_transform
			player.camera_pivot.rotation = Vector3.ZERO
			player.checkpoint_camera_rotation = Vector3.ZERO
	if transition_style == 1 and in_city:
		_set_flashback_effect_enabled(true)
	laboratory_energy = laboratory_light.light_energy
	var layer := CanvasLayer.new()
	layer.layer = 7 # Above the flashback effect and HUD, below the pause menu (layer 10).
	add_child(layer)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_material = ShaderMaterial.new()
	fade_material.shader = preload("res://scripts/flashback_fade.gdshader") if transition_style == 1 else preload("res://scripts/location_fade.gdshader")
	fade_material.set_shader_parameter("darkness", 0.0)
	if transition_style == 1:
		fade_material.set_shader_parameter("blur_amount", 0.0)
	veil.material = fade_material
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	veil.hide()
	$LaboratoryExit.body_entered.connect(_on_exit.bind(true))
	var return_area := city_room.get_node_or_null("ReturnArea") as Area3D
	if return_area != null:
		return_area.body_entered.connect(_on_exit.bind(false))
	# Both routes use one continuous ambience, rather than stacking two hums.
	ambience = player.get_node_or_null("TransitionAmbience") as AudioStreamPlayer
	transition_sound = AudioStreamPlayer.new()
	transition_sound.name = "TransitionSound"
	transition_sound.stream = TRANSITION_STREAM
	transition_sound.volume_db = -6.0
	transition_sound.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(transition_sound)
	if ambience != null:
		return
	# A quiet, continuous electrical tone bridges the blackout without a cut.
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = 22050
	var samples := PackedByteArray()
	samples.resize(44100)
	for i in range(22050):
		var wave := sin(TAU * 110.0 * i / 22050.0) * 0.6 + sin(TAU * 220.0 * i / 22050.0) * 0.15
		samples.encode_s16(i * 2, int(wave * 2400.0))
	sound.data = samples
	ambience = AudioStreamPlayer.new()
	ambience.name = "TransitionAmbience"
	ambience.stream = sound
	ambience.volume_db = -26.0
	player.add_child(ambience)
	ambience.play()

func _on_checkpoint_restored(location_id: String) -> void:
	if transitioning:
		return
	in_city = location_id == destination_location_id
	if transition_style == 1 and location_id in [source_location_id, destination_location_id]:
		_set_flashback_effect_enabled(in_city)
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	if location_id == source_location_id and laboratory_environment != null:
		# Laboratory checkpoints must always restore the original laboratory
		# environment, regardless of which outdoor weather was active before them.
		camera.environment = laboratory_environment
	elif in_city and destination_environment != null:
		camera.environment = destination_environment
	elif camera.environment == destination_environment and destination_environment != null:
		camera.environment = laboratory_environment
	location_changed.emit(in_city)

func _physics_process(_delta: float) -> void:
	if player.has_meta("developer_tools_open") or player.has_meta("cutscene_active"):
		return
	# Retry an occupied entrance after a swap or another transition finishes.
	if transitioning or player.swap_in_progress or player.has_meta("location_transition_active"):
		return
	var area: Area3D = city_room.get_node_or_null("ReturnArea") if in_city else $LaboratoryExit
	if area != null and area.overlaps_body(player):
		_on_exit(player, not in_city)

func _on_exit(body: Node3D, to_city: bool) -> void:
	if player.has_meta("developer_tools_open") or player.has_meta("cutscene_active"):
		return
	if body != player or transitioning or to_city == in_city:
		return
	if player.swap_in_progress:
		return
	if player.has_meta("location_transition_active"):
		return
	var entrance: Area3D = $LaboratoryExit if to_city else city_room.get_node_or_null("ReturnArea")
	if entrance == null:
		entrance = $LaboratoryExit
	transition_style = entrance.transition_style
	if transition_style == 1 and not to_city:
		# Fade the effect out while the player is still in the flashback.
		_set_flashback_effect_enabled(false)
	fade_material.shader = preload("res://scripts/flashback_fade.gdshader") if transition_style == 1 else preload("res://scripts/location_fade.gdshader")
	fade_material.set_shader_parameter("darkness", 0.0)
	if transition_style == 1:
		fade_material.set_shader_parameter("blur_amount", 0.0)
		fade_material.set_shader_parameter("light_tint", entrance.light_tint)
	player.set_meta("location_transition_active", true)
	transitioning = true
	if transition_style == 0 and to_city:
		laboratory_energy = laboratory_light.light_energy
		laboratory_dimmed = true
	transition_sound.play()
	veil.show()
	# Physical grabs stay in the source room; a pocket item travels in the hand.
	player._release_object()
	player.e_hold_pending = false
	player.e_hold_elapsed = 0.0
	player._set_placement_mode(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.velocity = Vector3.ZERO
	player.clear_swap_selection()
	var fade := create_tween().set_parallel(true)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(fade_material, "shader_parameter/darkness", 1.0, fade_out_duration)
	if transition_style == 1:
		fade.tween_property(fade_material, "shader_parameter/blur_amount", 1.0, fade_out_duration)
	if transition_style == 0 and to_city:
		fade.tween_property(laboratory_light, "light_energy", 0.0, fade_out_duration)
	fade.tween_property(ambience, "pitch_scale", 0.8 if to_city else 1.0, fade_out_duration)
	await fade.finished
	var arrival: Marker3D = city_room.get_node("Arrival") if to_city else $LaboratoryArrival
	player.global_transform = arrival.global_transform
	player.camera_pivot.rotation = Vector3.ZERO
	if destination_environment != null:
		var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
		if to_city:
			source_environment = laboratory_environment if laboratory_environment != null else camera.environment
			camera.environment = destination_environment
		else:
			camera.environment = laboratory_environment if laboratory_environment != null else source_environment
	player.reset_physics_interpolation()
	in_city = to_city
	if transition_style == 1 and to_city:
		# The destination is now active; the laboratory never receives this shader.
		_set_flashback_effect_enabled(true)
	location_changed.emit(to_city)
	player.clear_swap_selection()
	var next_location := destination_location_id if to_city else source_location_id
	get_node("/root/SaveManager").save_player_checkpoint(player, "%s_entrance" % next_location, next_location, arrival.global_transform)
	if not to_city and laboratory_dimmed:
		laboratory_light.light_energy = laboratory_energy
		laboratory_dimmed = false
	await get_tree().create_timer(black_hold_duration, false).timeout
	var reveal := create_tween().set_parallel(true)
	reveal.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(fade_material, "shader_parameter/darkness", 0.0, fade_in_duration)
	if transition_style == 1:
		# Clear the blur during the reveal so the white veil is always removed promptly.
		reveal.tween_property(fade_material, "shader_parameter/blur_amount", 0.0, minf(blur_clear_duration, fade_in_duration))
	await reveal.finished
	fade_material.set_shader_parameter("darkness", 0.0)
	if transition_style == 1:
		fade_material.set_shader_parameter("blur_amount", 0.0)
	veil.hide()
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	transitioning = false
	player.remove_meta("location_transition_active")
	if transition_style == 1:
		player.gameplay_action.emit(&"flashback_enter" if to_city else &"flashback_return")
	else:
		player.gameplay_action.emit(&"location_enter" if to_city else &"location_return")

func request_transition(to_city: bool) -> bool:
	if transitioning or to_city == in_city or player.swap_in_progress or player.has_meta("location_transition_active") or player.has_meta("cutscene_active") or player.has_meta("developer_tools_open"):
		return false
	_on_exit(player, to_city)
	return transitioning

func _set_flashback_effect_enabled(enabled: bool) -> void:
	if not is_instance_valid(flashback_effect):
		return
	if enabled:
		flashback_effect.call("start_flashback_effect")
	else:
		flashback_effect.call("stop_flashback_effect")
