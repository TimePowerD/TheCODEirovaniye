extends RigidBody3D

@export var physics_enabled: bool = true:
	set(value):
		physics_enabled = value
		freeze = not value

func _ready() -> void:
	freeze = not physics_enabled
	collision_layer = 2
	collision_mask = 3
