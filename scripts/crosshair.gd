extends Control

const INTERACTION_CURSOR: Texture2D = preload("res://assets/models/icons/PNG/Basic/Default/gauntlet_open.png")

var interaction_target := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_interaction_target(active: bool) -> void:
	if interaction_target == active:
		return
	interaction_target = active
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if interaction_target:
		var cursor_size := Vector2(28.0, 28.0)
		draw_texture_rect(INTERACTION_CURSOR, Rect2(center - cursor_size * 0.5, cursor_size), false)
	else:
		draw_circle(center, 3.0, Color(1.0, 1.0, 1.0, 0.8), true, -1.0, true)
