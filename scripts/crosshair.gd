extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, 3.0, Color(1.0, 1.0, 1.0, 0.8), true, -1.0, true)
