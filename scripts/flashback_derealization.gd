extends CanvasLayer
## Controls the full-screen derealization effect used only in flashback scenes.

@export_range(0.1, 5.0, 0.1) var fade_in_duration := 1.5
@export_range(0.1, 5.0, 0.1) var fade_out_duration := 2.0
@export var preview_on_ready := false
@export_range(0.0, 0.02, 0.001) var chromatic_strength := 0.003
@export_range(0.0, 0.02, 0.001) var blur_strength := 0.004
@export_range(0.0, 0.03, 0.001) var distortion_strength := 0.006
@export_range(0.0, 1.0, 0.01) var desaturation_strength := 0.28
@export_range(0.0, 0.25, 0.005) var double_vision_strength := 0.055
@export_range(0.0, 1.0, 0.01) var vignette_strength := 0.28
@export_range(0.0, 0.1, 0.001) var noise_strength := 0.018

var intensity := 0.0
var _effect_tween: Tween
var _run_id := 0
var _effect_rect: ColorRect
var _effect_material: ShaderMaterial

func _ready() -> void:
	layer = 4
	_effect_rect = ColorRect.new()
	_effect_rect.name = "DerealizationOverlay"
	_effect_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_rect.visible = false
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = preload("res://scripts/flashback_derealization.gdshader")
	_effect_material.set_shader_parameter("intensity", 0.0)
	_effect_material.set_shader_parameter("chromatic_strength", chromatic_strength)
	_effect_material.set_shader_parameter("blur_strength", blur_strength)
	_effect_material.set_shader_parameter("distortion_strength", distortion_strength)
	_effect_material.set_shader_parameter("desaturation_strength", desaturation_strength)
	_effect_material.set_shader_parameter("double_vision_strength", double_vision_strength)
	_effect_material.set_shader_parameter("vignette_strength", vignette_strength)
	_effect_material.set_shader_parameter("noise_strength", noise_strength)
	_effect_rect.material = _effect_material
	add_child(_effect_rect)
	if preview_on_ready:
		start_flashback_effect()

func start_flashback_effect(duration: float = -1.0) -> void:
	if _effect_rect == null:
		return
	_run_id += 1
	_stop_active_tween()
	_effect_rect.show()
	var fade_duration := fade_in_duration if duration < 0.0 else maxf(duration, 0.0)
	_effect_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_effect_tween.tween_method(_apply_intensity, intensity, 1.0, fade_duration)

func stop_flashback_effect(duration: float = -1.0) -> void:
	if _effect_rect == null:
		return
	_run_id += 1
	_stop_active_tween()
	var fade_duration := fade_out_duration if duration < 0.0 else maxf(duration, 0.0)
	var this_run := _run_id
	_effect_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_effect_tween.tween_method(_apply_intensity, intensity, 0.0, fade_duration)
	_effect_tween.tween_callback(_hide_if_still_stopped.bind(this_run))

func _apply_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	if _effect_material != null:
		_effect_material.set_shader_parameter("intensity", intensity)

func _hide_if_still_stopped(run_id: int) -> void:
	if run_id == _run_id and intensity <= 0.001 and _effect_rect != null:
		_effect_rect.hide()

func _stop_active_tween() -> void:
	if _effect_tween != null and _effect_tween.is_running():
		_effect_tween.kill()
	_effect_tween = null
