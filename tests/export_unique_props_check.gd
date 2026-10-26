extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
	await scene_changed
	await process_frame
	var walls := current_scene.get_node("LabModuleLibrary/Walls")
	for root_name in ["ladderProp2", "ventObject2"]:
		var root := walls.get_node(root_name)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "%s contains %d rendered meshes" % [root_name, meshes.size()])
		assert(meshes[0].is_visible_in_tree(), "%s has no visible mesh" % root_name)
	print("PASS: ladder and vent each contain exactly one rendered mesh")
	quit()
