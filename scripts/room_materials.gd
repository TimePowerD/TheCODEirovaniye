@tool
extends Node3D

const FLOOR_MATERIAL: StandardMaterial3D = preload("res://assets/materials/lab_floor.tres")
const WALL_MATERIAL: StandardMaterial3D = preload("res://assets/materials/lab_wall.tres")

func _ready() -> void:
	_apply_materials()

func _apply_materials() -> void:
	_assign_material("Room/Floor/FloorModel/labFloor2x1entr", FLOOR_MATERIAL)
	_assign_material("Room/Ceiling/CeilingModel/labCeiling1x1", FLOOR_MATERIAL)
	_assign_material("Room/Ceiling/CorridorCeilingModel/labCeiling1x1", FLOOR_MATERIAL)

	for mesh_path in [
		"Room/MainWallEast/WallModel/labWall1x1",
		"Room/MainWallWest/WallModel/labWall1x1",
		"Room/MainWallNorth/WallModel/labWall1x1",
		"Room/DoorWall/DoorWallModel/labWallEntr",
		"Room/CorridorWallEast/WallModel/labWall1x1",
		"Room/CorridorWallWest/WallModel/labWall1x1",
		"Room/CorridorEndWall/WallModel/labWall1x1",
	]:
		_assign_material(mesh_path, WALL_MATERIAL)

func _assign_material(mesh_path: String, material: StandardMaterial3D) -> void:
	var mesh_instance := get_node_or_null(mesh_path) as MeshInstance3D
	if mesh_instance != null:
		mesh_instance.material_override = material
