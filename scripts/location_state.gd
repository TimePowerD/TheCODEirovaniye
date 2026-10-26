extends Node

signal location_changed(location_id: String)

var current_location_id := "laboratory"
var initial_player_transform := Transform3D.IDENTITY

func initialize_scene(player: CharacterBody3D) -> void:
	initial_player_transform = player.global_transform
	set_current_location("laboratory")

func set_current_location(location_id: String) -> void:
	if current_location_id == location_id:
		return
	current_location_id = location_id
	location_changed.emit(location_id)
