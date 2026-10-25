extends StaticBody3D

signal activated
signal deactivated
signal toggled(is_active: bool)

@onready var handle: Node3D = $Handle
var is_active := false
var initial_handle_rotation := Vector3.ZERO

func _ready() -> void:
	add_to_group("interactable")
	initial_handle_rotation = handle.rotation

func reset_state() -> void:
	is_active = false
	handle.rotation = initial_handle_rotation

func interact(_user: Node3D) -> void:
	is_active = not is_active
	var target_angle := deg_to_rad(-35.0 if is_active else 35.0)
	var tween := create_tween()
	tween.tween_property(handle, "rotation:z", target_angle, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toggled.emit(is_active)
	if is_active:
		activated.emit()
	else:
		deactivated.emit()
