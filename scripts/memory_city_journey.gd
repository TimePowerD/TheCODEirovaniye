extends Node
## The final memory: ventilation -> stormy city -> the house at the far end.

@export var player: CharacterBody3D
@export var weather: Node
@export var light_path: Node3D

var active := false

func _ready() -> void:
	get_node("/root/LocationState").location_changed.connect(_on_location_changed)
	# Weather and the other location controllers finish _ready first.
	call_deferred("_sync_location")

func _sync_location() -> void:
	_on_location_changed(get_node("/root/LocationState").current_location_id)

func _on_location_changed(location_id: String) -> void:
	active = location_id == "flashback"
	weather.set_story_storm(active)
	light_path.set_active(active, active)
	if location_id == "kitchen":
		# An indoor location must not retain the outdoor screen distortion.
		var effect := get_node_or_null("../FlashbackDerealization")
		if effect != null:
			effect.stop_flashback_effect(0.0)
