extends Node

## A slow blackout links the laboratory to an apparently remembered city room.
@export var city_room: Node3D
@export var player: CharacterBody3D
@export var laboratory_light: OmniLight3D
@export_enum("Dark", "Flashback") var transition_style: int = 0
@export_range(0.1, 5.0, 0.05) var fade_out_duration: float = 1.2
@export_range(0.0, 3.0, 0.05) var black_hold_duration: float = 0.65
@export_range(0.1, 5.0, 0.05) var fade_in_duration: float = 2.0
@export_range(0.1, 10.0, 0.05) var blur_clear_duration: float = 3.0

var transitioning := false
var in_city := false
var veil: ColorRect
var fade_material: ShaderMaterial
var ambience: AudioStreamPlayer
var laboratory_energy: float

func _ready() -> void:
	transition_style = $LaboratoryExit.transition_style
	laboratory_energy = laboratory_light.light_energy
	var layer := CanvasLayer.new()
	layer.layer = 30
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
	city_room.get_node("ReturnArea").body_entered.connect(_on_exit.bind(false))
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
	ambience.stream = sound
	ambience.volume_db = -26.0
	add_child(ambience)
	ambience.play()

func _on_exit(body: Node3D, to_city: bool) -> void:
	if body != player or transitioning or to_city == in_city:
		return
	if player.swap_in_progress:
		return
	if player.has_meta("location_transition_active"):
		return
	player.set_meta("location_transition_active", true)
	transitioning = true
	veil.show()
	# Physical grabs stay in the source room; a pocket item travels in the hand.
	player._release_object()
	player.e_hold_pending = false
	player.e_hold_elapsed = 0.0
	player._set_placement_mode(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.velocity = Vector3.ZERO
	player.selected_target = null
	player.hovered_target = null
	player.suppressed_hover_outline = null
	player._refresh_outlines()
	var fade := create_tween().set_parallel(true)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(fade_material, "shader_parameter/darkness", 1.0, fade_out_duration)
	if transition_style == 1:
		fade.tween_property(fade_material, "shader_parameter/blur_amount", 1.0, fade_out_duration)
	if transition_style == 0:
		fade.tween_property(laboratory_light, "light_energy", 0.0, fade_out_duration)
	fade.tween_property(ambience, "pitch_scale", 0.8 if to_city else 1.0, fade_out_duration)
	await fade.finished
	var arrival: Marker3D = city_room.get_node("Arrival") if to_city else $LaboratoryArrival
	player.global_transform = arrival.global_transform
	player.checkpoint_transform = arrival.global_transform
	player.camera_pivot.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	in_city = to_city
	if not to_city and transition_style == 0:
		laboratory_light.light_energy = laboratory_energy
	await get_tree().create_timer(black_hold_duration, false).timeout
	var reveal := create_tween()
	reveal.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(fade_material, "shader_parameter/darkness", 0.0, fade_in_duration)
	await reveal.finished
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	if transition_style == 1:
		var clear_blur := create_tween()
		clear_blur.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		clear_blur.tween_property(fade_material, "shader_parameter/blur_amount", 0.0, blur_clear_duration)
		await clear_blur.finished
	veil.hide()
	transitioning = false
	player.remove_meta("location_transition_active")
