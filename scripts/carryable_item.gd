extends RigidBody3D

signal used(user: Node3D)

@export var physics_enabled: bool = true:
	set(value):
		physics_enabled = value
		freeze = not value
@export var item_name: String = "Предмет"
@export var can_use: bool = true

func _ready() -> void:
	freeze = not physics_enabled
	collision_layer = 2
	collision_mask = 3
	add_to_group("carryable")
	add_to_group("swapAble")

func use_item(user: Node3D) -> void:
	if not can_use:
		return
	used.emit(user)
	print("Использован предмет: %s" % item_name)
