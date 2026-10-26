extends "res://scripts/location_transition.gd"
## White flashback between the laboratory and the winding forest trail.

const FOREST_AMBIENCE_STREAM: AudioStreamOggVorbis = preload("res://assets/audio/final sounds/forest_birds.ogg")

var forest_ambience: AudioStreamPlayer

func _ready() -> void:
	super._ready()
	var loop_stream := FOREST_AMBIENCE_STREAM.duplicate() as AudioStreamOggVorbis
	loop_stream.loop = true
	forest_ambience = AudioStreamPlayer.new()
	forest_ambience.name = "ForestBirdAmbience"
	forest_ambience.stream = loop_stream
	forest_ambience.volume_db = -16.0
	add_child(forest_ambience)
	location_changed.connect(_set_forest_active)
	_set_forest_active(in_city)
	if in_city:
		(player.get_node("CameraPivot/Camera3D") as Camera3D).environment = destination_environment

func _set_forest_active(active: bool) -> void:
	city_room.visible = active
	city_room.get_node("ForestSun").visible = active
	if active:
		if not forest_ambience.playing:
			forest_ambience.play()
	else:
		forest_ambience.stop()
