extends StaticBody3D

signal activated
signal deactivated
signal weight_changed(current_weight: float, required_weight: float)

@export_range(0.1, 1000.0, 0.1) var minimum_weight: float = 1.0
@export_range(0.1, 500.0, 0.1) var player_weight: float = 75.0
@export_range(0.1, 1000.0, 0.1) var default_object_weight: float = 1.0

@onready var occupants: Area3D = $WeightArea
@onready var plate_visual: MeshInstance3D = $PlateVisual

var is_active := false
var is_weight_plate := true
var bodies_inside: Array[Node3D] = []

func _ready() -> void:
	add_to_group("interactable")
	occupants.body_entered.connect(_on_body_entered)
	occupants.body_exited.connect(_on_body_exited)
	_recalculate_weight()

func _on_body_entered(body: Node3D) -> void:
	if not bodies_inside.has(body):
		bodies_inside.append(body)
	_recalculate_weight()

func _on_body_exited(body: Node3D) -> void:
	bodies_inside.erase(body)
	_recalculate_weight()

func _recalculate_weight() -> void:
	var current_weight := 0.0
	for body in bodies_inside:
		if not is_instance_valid(body):
			continue
		if body.is_in_group("player"):
			current_weight += player_weight
		elif body is PhysicsBody3D and not body.is_in_group("carryable"):
			if body is RigidBody3D:
				current_weight += (body as RigidBody3D).mass
			else:
				current_weight += default_object_weight
	var should_be_active := current_weight >= minimum_weight
	weight_changed.emit(current_weight, minimum_weight)
	if should_be_active == is_active:
		return
	is_active = should_be_active
	plate_visual.position.y = -0.035 if is_active else 0.0
	if is_active:
		print("Нажимная плита активирована: %.1f / %.1f кг" % [current_weight, minimum_weight])
		activated.emit()
	else:
		print("Нажимная плита деактивирована: %.1f / %.1f кг" % [current_weight, minimum_weight])
		deactivated.emit()
