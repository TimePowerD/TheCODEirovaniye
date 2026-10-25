@tool
extends Node3D

@onready var imported_model: Node3D = $ImportedModel

func _ready() -> void:
	var pending: Array[Node] = [imported_model]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Camera3D:
			(node as Camera3D).current = false
			node.queue_free()
		elif node is Light3D:
			node.queue_free()
		else:
			pending.append_array(node.get_children())
