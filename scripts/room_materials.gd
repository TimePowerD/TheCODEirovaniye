@tool
extends Node3D

const FLOOR_MATERIAL: StandardMaterial3D = preload("res://assets/materials/lab_floor.tres")
const WALL_MATERIAL: StandardMaterial3D = preload("res://assets/materials/lab_wall.tres")

func _ready() -> void:
	_apply_materials()

func _apply_materials() -> void:
	_apply_materials_recursive(self)

func _apply_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_name := node.name.to_lower()
		if mesh_name.begins_with("labwall"):
			node.material_override = WALL_MATERIAL
		elif mesh_name.begins_with("labfloor") or mesh_name.begins_with("labceiling"):
			node.material_override = FLOOR_MATERIAL

	for child in node.get_children():
		_apply_materials_recursive(child)
