extends Node3D
## The saved scene contains the layout; this script only controls its practical lights.
var lamps: Array[Light3D] = []
var windows: Array[StandardMaterial3D] = []
var lighting_strength := -1.0

func _ready() -> void:
	for node in find_children("*", "Light3D", true, false):
		if node.is_in_group("city_night_light"):
			lamps.append(node)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta("city_window_surface"):
			continue
		var material: Material = mesh.get_active_material(int(mesh.get_meta("city_window_surface")))
		if material is StandardMaterial3D and material not in windows:
			windows.append(material)
	set_night_lighting(0.0)

func set_night_lighting(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if absf(amount - lighting_strength) < 0.002:
		return
	lighting_strength = amount
	for lamp in lamps:
		lamp.light_energy = float(lamp.get_meta("night_energy", 1.5)) * amount
		lamp.visible = amount > 0.005
	for material in windows:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.62, 0.22)
		material.emission_energy_multiplier = amount * 2.8
		material.albedo_color = Color.WHITE.lerp(Color(1.0, 0.82, 0.54), amount)

func set_city_active(active: bool) -> void:
	$Traffic.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if not active:
		set_night_lighting(0.0)

