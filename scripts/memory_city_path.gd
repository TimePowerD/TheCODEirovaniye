extends Node3D
## A one-way trail through the remembered city. Consumed lights stay extinguished
## until the story controller explicitly starts a new visit with reset_progress.

const LIGHT_SPACING := 3.5
const PATCH_HEIGHT := 0.09 # Above pavement (0.04) and crosswalk stripes (0.06).
const LIGHT_ENERGY := 0.42
const PATCH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float soft_edge = 1.0 - smoothstep(0.15, 1.0, radius);
	vec3 tint = vec3(0.78, 0.63, 0.37);
	ALBEDO = tint;
	EMISSION = tint * 0.16 * amount;
	ALPHA = soft_edge * 0.28 * amount;
}
"""

@export_range(0.1, 3.0, 0.05) var fade_duration := 0.85

var active := false
var segments: Array[Dictionary] = []

func _ready() -> void:
	_build_trail()
	set_active(active)

func set_active(value: bool, reset_progress: bool = false) -> void:
	active = value
	visible = active
	set_physics_process(active)
	for segment in segments:
		var tween := segment["tween"] as Tween
		if tween != null and tween.is_valid():
			tween.kill()
		segment["tween"] = null
		if reset_progress:
			segment["consumed"] = false
		var consumed: bool = segment["consumed"]
		var illuminated := active and not consumed
		segment["area"].set_deferred("monitoring", active and not consumed)
		segment["root"].visible = illuminated
		segment["material"].set_shader_parameter("amount", 1.0 if illuminated else 0.0)
		segment["light"].light_energy = LIGHT_ENERGY if illuminated else 0.0

func _build_trail() -> void:
	var shader := Shader.new()
	shader.code = PATCH_SHADER
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.6, 2.6)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.8, 2.4)
	var points := PackedVector3Array([
		Vector3(0.0, PATCH_HEIGHT, 0.0),
		Vector3(0.0, PATCH_HEIGHT, -120.0),
		Vector3(-2.0, PATCH_HEIGHT, -124.0),
		Vector3(-2.0, PATCH_HEIGHT, -126.65),
	])
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	for point in points:
		curve.add_point(point)
	var length_ := curve.get_baked_length()
	var count := int(ceil(length_ / LIGHT_SPACING))
	for index in range(count + 1):
		var segment_root := Node3D.new()
		segment_root.name = "TrailLight%02d" % index
		segment_root.position = curve.sample_baked(minf(index * LIGHT_SPACING, length_))
		add_child(segment_root)
		var material := ShaderMaterial.new()
		material.shader = shader
		var patch := MeshInstance3D.new()
		patch.name = "GroundGlow"
		patch.mesh = mesh
		patch.material_override = material
		patch.rotation.x = -PI * 0.5
		patch.layers = 2
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment_root.add_child(patch)
		var light := OmniLight3D.new()
		light.name = "SoftLight"
		light.position.y = 0.45
		light.light_color = Color(1.0, 0.74, 0.42)
		light.light_energy = LIGHT_ENERGY
		light.omni_range = 3.8
		light.omni_attenuation = 1.5
		light.light_cull_mask = 2
		light.layers = 2
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 12.0
		light.distance_fade_length = 5.0
		segment_root.add_child(light)
		var area := Area3D.new()
		area.name = "WalkThrough"
		area.position.y = 1.1
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = false
		area.monitorable = false
		segment_root.add_child(area)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		area.add_child(collision)
		segments.append({
			"root": segment_root, "area": area, "material": material,
			"light": light, "consumed": false, "tween": null,
		})

func _physics_process(_delta: float) -> void:
	if not active or get_tree().paused:
		return
	for segment in segments:
		if segment["consumed"]:
			continue
		var area := segment["area"] as Area3D
		# Poll overlaps so entering during the flashback does not lose the event:
		# the light fades only after the player regains control and can walk.
		for body in area.get_overlapping_bodies():
			if not body is CharacterBody3D or not body.is_in_group("player"):
				continue
			if body.has_meta("location_transition_active") or body.has_meta("cutscene_active"):
				continue
			_fade_segment(segment)
			break

func _fade_segment(segment: Dictionary) -> void:
	segment["consumed"] = true
	segment["area"].set_deferred("monitoring", false)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	segment["tween"] = tween
	tween.tween_property(segment["material"], "shader_parameter/amount", 0.0, fade_duration)
	tween.tween_property(segment["light"], "light_energy", 0.0, fade_duration)
	tween.chain().tween_callback(segment["root"].hide)
