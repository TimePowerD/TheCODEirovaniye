extends StaticBody3D

signal activated
signal deactivated
signal weight_changed(current_weight: float, required_weight: float)

@export_range(0.1, 1000.0, 0.1) var minimum_weight: float = 2.0
@export_range(0.1, 500.0, 0.1) var player_weight: float = 75.0
@export_range(0.1, 1000.0, 0.1) var default_object_weight: float = 1.0

@onready var occupants: Area3D = $WeightArea
@onready var plate_visual: Node3D = $LabButton
@onready var button_visual: MeshInstance3D = get_node_or_null("LabButton/Cube_001") as MeshInstance3D

var is_active := false
var is_weight_plate := true
var bodies_inside: Array[Node3D] = []
var initial_visual_position := Vector3.ZERO
var button_tween: Tween

const BUTTON_PRESS_DURATION := 0.18

func _ready() -> void:
	add_to_group("interactable")
	initial_visual_position = plate_visual.position
	occupants.body_entered.connect(_on_body_entered)
	occupants.body_exited.connect(_on_body_exited)
	_recalculate_weight()

func reset_state() -> void:
	bodies_inside.clear()
	is_active = false
	plate_visual.position = initial_visual_position
	if button_tween != null and button_tween.is_running():
		button_tween.kill()
	if is_instance_valid(button_visual) and button_visual.mesh != null:
		for blend_shape_index in range(button_visual.mesh.get_blend_shape_count()):
			button_visual.set_blend_shape_value(blend_shape_index, 0.0)

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
	plate_visual.position.y = initial_visual_position.y - 0.035 if is_active else initial_visual_position.y
	_animate_button(is_active)
	if is_active:
		print("Нажимная плита активирована: %.1f / %.1f кг" % [current_weight, minimum_weight])
		activated.emit()
	else:
		print("Нажимная плита деактивирована: %.1f / %.1f кг" % [current_weight, minimum_weight])
		deactivated.emit()

func _animate_button(should_press: bool) -> void:
	if not is_instance_valid(button_visual) or button_visual.mesh == null:
		return
	if button_tween != null and button_tween.is_running():
		button_tween.kill()
	if button_visual.mesh.get_blend_shape_count() == 0:
		return
	var blend_shape_name: StringName = button_visual.mesh.get_blend_shape_name(0)
	var blend_target := 1.0 if should_press else 0.0
	button_tween = create_tween()
	button_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	button_tween.tween_property(button_visual, "blend_shapes/%s" % blend_shape_name, blend_target, BUTTON_PRESS_DURATION)
