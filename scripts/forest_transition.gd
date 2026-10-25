extends "res://scripts/location_transition.gd"
## White flashback between the laboratory and the winding forest trail.

func _ready() -> void:
	super._ready()
	location_changed.connect(_set_forest_active)
	_set_forest_active(in_city)
	if in_city:
		(player.get_node("CameraPivot/Camera3D") as Camera3D).environment = destination_environment

func _set_forest_active(active: bool) -> void:
	city_room.visible = active
	city_room.get_node("ForestSun").visible = active
