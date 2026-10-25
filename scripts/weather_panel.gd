extends Node3D
## Reusable world console. Buttons are physical bodies reached by the player's ray.
@export var controller: Node
@export_flags_3d_render var visual_layer: int = 1
var buttons: Array[StaticBody3D] = []
var lights: Array[StandardMaterial3D] = []
const TITLES = ["1 — Солнечно", "2 — Тёплый вечер", "3 — Пасмурно", "4 — Гроза"]

func _ready() -> void:
	var backing := StaticBody3D.new()
	backing.name = "Backing"
	add_child(backing)
	_box(backing, Vector3(1.75, 1.5, 0.18), Vector3(0, 1.35, 0), Color(0.12, 0.16, 0.19))
	_box(backing, Vector3(0.18, 0.6, 0.18), Vector3(0, 0.3, 0), Color(0.12, 0.16, 0.19))
	_box(backing, Vector3(0.7, 0.08, 0.45), Vector3(0, 0.04, 0), Color(0.12, 0.16, 0.19))
	_label("ПОГОДА НА УЛИЦЕ", Vector3(0, 2.28, 0.12), 28)
	for i in range(4):
		var body := StaticBody3D.new()
		body.name = "WeatherButton%d" % i
		body.position = Vector3(0, 1.88 - i * 0.36, 0.17)
		body.set_meta("weather_mode", i)
		body.add_to_group("weather_button")
		add_child(body)
		var material := _box(body, Vector3(1.55, 0.29, 0.16), Vector3.ZERO, Color(0.27, 0.32, 0.35))
		material.emission_enabled = true
		lights.append(material)
		buttons.append(body)
		_label(TITLES[i], body.position + Vector3(0, 0, 0.09), 23)
	controller.weather_changed.connect(_sync)
	_sync(controller.mode)

func activate(index: int) -> bool:
	if not controller.in_street:
		return false
	return controller.set_weather(index)

func _sync(index: int) -> void:
	for i in range(lights.size()):
		lights[i].albedo_color = Color(0.32, 0.62, 0.4) if i == index else Color(0.27, 0.32, 0.35)
		lights[i].emission = Color(0.12, 0.38, 0.18) if i == index else Color.BLACK

func _box(body: StaticBody3D, size: Vector3, at: Vector3, color: Color) -> StandardMaterial3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.layers = visual_layer
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	return material

func _label(text: String, at: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = Color(0.95, 0.97, 1)
	label.no_depth_test = false
	label.layers = visual_layer
	add_child(label)
