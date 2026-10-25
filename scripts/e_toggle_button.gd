extends StaticBody3D

signal activated
signal deactivated
signal pressed(is_active: bool)

@onready var button_visual: MeshInstance3D = $ButtonVisual
var is_active := false

func _ready() -> void:
	add_to_group("interactable")

func interact(_user: Node3D) -> void:
	is_active = not is_active
	button_visual.position.y = 0.08 if is_active else 0.16
	pressed.emit(is_active)
	if is_active:
		activated.emit()
	else:
		deactivated.emit()
