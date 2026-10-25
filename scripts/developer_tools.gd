extends CanvasLayer

## Temporary tools. Release exports always remove this UI.
@export var enabled: bool = true
@export var player: CharacterBody3D
@export var menu: CanvasLayer
var panel: PanelContainer
var launcher: Button
var status: Label
var objects := []
var opened := false
var saved_physics := true
var saved_input := true
var trigger_picker: OptionButton
var cutscene_picker: OptionButton
var markers: Array[Area3D] = []
var cutscenes: Array[Node] = []
var debug_meshes: Array[Node] = []
var selected_object: Node3D
var selection_label: Label
var delete_button: Button
var selection_overlay: ShaderMaterial
var previous_overlays: Dictionary = {}
var looking := false

func _ready() -> void:
	if not enabled or not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	launcher = Button.new()
	launcher.text = "F1 · Инструменты разработки"
	launcher.position = Vector2(16, 16)
	launcher.pressed.connect(toggle)
	add_child(launcher)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 58)
	panel.custom_minimum_size = Vector2(370, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.065, 0.97)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370, 440)
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	_label(content, "РАЗРАБОТКА · F1 / Esc — закрыть")
	_label(content, "WASD / Shift / Пробел — движение\nПКМ вне панели — обзор; ЛКМ — выбор")
	_label(content, "Объекты перед камерой")
	_button(content, "Создать куб для обмена", spawn_object.bind(false))
	_button(content, "Создать предмет для подбора", spawn_object.bind(true))
	selection_label = _label(content, "ЛКМ по созданному предмету — выбрать")
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.custom_minimum_size.x = 320
	delete_button = _button(content, "Удалить выбранный предмет", delete_selected)
	delete_button.disabled = true
	_button(content, "Удалить созданные объекты", clear_objects)
	_label(content, "Переходы / эффекты")
	_button(content, "Городская комната — затемнение", run_transition.bind("LocationTransition"))
	_button(content, "Солнечная улица — флэшбэк", run_transition.bind("FlashbackTransition"))
	_button(content, "Вернуться в лабораторию", return_to_lab)
	_label(content, "Проверка зон входа")
	trigger_picker = OptionButton.new()
	trigger_picker.fit_to_longest_item = false
	content.add_child(trigger_picker)
	_button(content, "Переместиться внутрь выбранной зоны", enter_trigger)
	_button(content, "Показать / скрыть границы триггеров", toggle_markers)
	_label(content, "Кат-сцены")
	cutscene_picker = OptionButton.new()
	cutscene_picker.fit_to_longest_item = false
	content.add_child(cutscene_picker)
	_button(content, "Запустить выбранную кат-сцену", play_cutscene)
	_label(content, "Пробел — пропустить пролёт камеры")
	_label(content, "Обучение")
	_button(content, "Начать обучение заново", restart_tutorial)
	_button(content, "Скрыть обучение", skip_tutorial)
	_button(content, "Обновить список триггеров и кат-сцен", refresh)
	status = _label(content, "Инструменты доступны только в debug-сборке.")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 320
	panel.hide()
	refresh()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _process(_delta: float) -> void:
	if selected_object != null and (not is_instance_valid(selected_object) or selected_object.is_queued_for_deletion()):
		_clear_selection()
	var playing: bool = menu.game_started and not get_tree().paused
	launcher.visible = playing
	panel.visible = playing and opened
	if opened and not playing:
		close()

func _input(event: InputEvent) -> void:
	if opened and looking and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		looking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or (opened and event.keycode == KEY_ESCAPE):
			toggle()
			get_viewport().set_input_as_handled()

func _busy() -> bool:
	return player.has_meta("location_transition_active") or player.has_meta("cutscene_active") or player.swap_in_progress

func _unhandled_input(event: InputEvent) -> void:
	if not opened or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not panel.get_global_rect().has_point(event.position) and not launcher.get_global_rect().has_point(event.position):
			looking = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if looking and event is InputEventMouseMotion:
		player.apply_look(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# GUI consumes its clicks first; also guard direct calls from tests/tools.
		if panel.get_global_rect().has_point(event.position) or launcher.get_global_rect().has_point(event.position):
			return
		select_at_screen_position(event.position)
		get_viewport().set_input_as_handled()

func select_at_screen_position(position: Vector2) -> void:
	if not opened:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(position)
	var end := origin + camera.project_ray_normal(position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 3, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	_clear_selection()
	if hit.is_empty() or hit.collider not in objects or hit.collider.is_queued_for_deletion():
		selection_label.text = "Не выбран созданный предмет"
		return
	selected_object = hit.collider
	selection_overlay = ShaderMaterial.new()
	selection_overlay.shader = preload("res://scripts/swap_outline.gdshader")
	selection_overlay.set_shader_parameter("outline_color", Color(0.2, 1.0, 0.85))
	for mesh in selected_object.find_children("*", "MeshInstance3D", true, false):
		previous_overlays[mesh] = mesh.material_overlay
		mesh.material_overlay = selection_overlay
	selection_label.text = "Выбран: %s" % selected_object.name
	delete_button.disabled = false

func _clear_selection() -> void:
	for mesh in previous_overlays:
		if is_instance_valid(mesh) and mesh.material_overlay == selection_overlay:
			mesh.material_overlay = previous_overlays[mesh]
	previous_overlays.clear()
	selection_overlay = null
	selected_object = null
	if is_instance_valid(delete_button):
		delete_button.disabled = true
	if is_instance_valid(selection_label):
		selection_label.text = "ЛКМ по созданному предмету — выбрать"

func delete_selected() -> void:
	if not opened or not is_instance_valid(selected_object) or selected_object not in objects:
		_clear_selection()
		return
	var target := selected_object
	_clear_selection()
	if player.held_object == target:
		player._release_object()
	if player.held_item == target:
		player._drop_item()
	if player.selected_target == target:
		player.selected_target = null
	if player.hovered_target == target:
		player.hovered_target = null
	if player.suppressed_hover_outline == target:
		player.suppressed_hover_outline = null
	player._refresh_outlines()
	objects.erase(target)
	target.queue_free()
	status.text = "Выбранный предмет удалён. Осталось: %d" % objects.size()

func toggle() -> void:
	if opened:
		close()
	elif menu.game_started and not get_tree().paused and not _busy():
		opened = true
		player.set_meta("developer_tools_open", true)
		saved_physics = player.is_physics_processing()
		saved_input = player.is_processing_unhandled_input()
		player._release_object()
		player.e_hold_pending = false
		player._set_placement_mode(false)
		player.selected_target = null
		player.hovered_target = null
		player.suppressed_hover_outline = null
		player._refresh_outlines()
		player.set_process_unhandled_input(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		panel.show()

func close() -> void:
	if not opened:
		return
	opened = false
	looking = false
	_clear_selection()
	panel.hide()
	player.remove_meta("developer_tools_open")
	player.set_physics_process(saved_physics)
	player.set_process_unhandled_input(saved_input)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED

func refresh() -> void:
	markers.clear()
	trigger_picker.clear()
	for area in get_tree().current_scene.find_children("*", "Area3D", true, false):
		if area.get_script() == preload("res://scripts/transition_marker.gd"):
			markers.append(area)
			trigger_picker.add_item(str(get_tree().current_scene.get_path_to(area)))
	cutscenes.clear()
	cutscene_picker.clear()
	for scene in get_tree().get_nodes_in_group("developer_cutscenes"):
		if scene.has_method("play"):
			cutscenes.append(scene)
			cutscene_picker.add_item(str(scene.name))
	cutscene_picker.disabled = cutscenes.is_empty()

func spawn_object(pickup: bool) -> Node3D:
	objects = objects.filter(func(node): return is_instance_valid(node))
	if objects.size() >= 50:
		status.text = "Лимит 50 объектов. Удалите созданные объекты."
		return null
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	var target := camera.global_position - camera.global_basis.z * 3.0
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target, 3, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		target = hit.position + hit.normal * 0.65
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, target)
	query.collision_mask = 3
	if not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		status.text = "Недостаточно места. Посмотрите на свободный участок."
		return null
	var object: RigidBody3D
	if pickup:
		object = preload("res://scenes/items/pickup_test_item.tscn").instantiate()
	else:
		object = RigidBody3D.new()
		object.set_script(preload("res://scripts/physics_object.gd"))
		object.add_to_group("swappable")
		object.add_to_group("swapAble")
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.7, 0.85)
		mesh.material_override = material
		object.add_child(mesh)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		object.add_child(collision)
	object.name = "DeveloperObject"
	get_tree().current_scene.add_child(object)
	object.global_position = target
	objects.append(object)
	status.text = "Объект создан. Всего: %d" % objects.size()
	return object

func clear_objects() -> void:
	_clear_selection()
	if player.held_object in objects:
		player._release_object()
	if player.held_item in objects:
		player._drop_item()
	for object in objects:
		if is_instance_valid(object):
			object.queue_free()
	objects.clear()
	status.text = "Созданные объекты удалены."

func run_transition(route_name: String) -> void:
	var route = get_tree().current_scene.find_child(route_name, true, false)
	for other in get_tree().current_scene.find_children("*", "Node", true, false):
		if other.get_script() == preload("res://scripts/location_transition.gd") and other != route and other.in_city:
			status.text = "Сначала вернитесь в лабораторию."
			return
	close()
	if not route.request_transition(true):
		status.text = "Переход занят или вы уже в этой комнате."

func return_to_lab() -> void:
	for route in get_tree().current_scene.find_children("*", "Node", true, false):
		if route.get_script() == preload("res://scripts/location_transition.gd") and route.in_city:
			close()
			route.request_transition(false)
			return
	status.text = "Вы уже в лаборатории."

func enter_trigger() -> void:
	if markers.is_empty():
		return
	var marker := markers[trigger_picker.selected]
	var route = marker.get_parent() if marker.name == "LaboratoryExit" else null
	if route != null and route.in_city:
		status.text = "Этот вход находится в лаборатории. Сначала вернитесь."
		return
	# Teleport only into zones belonging to the player's current location.
	var current_room: Node = null
	for candidate in get_tree().current_scene.find_children("*", "Node", true, false):
		if candidate.get_script() == preload("res://scripts/location_transition.gd") and candidate.in_city:
			current_room = candidate.city_room
	if (marker.name == "ReturnArea" and marker.get_parent() != current_room) or (marker.name == "LaboratoryExit" and current_room != null):
		status.text = "Выберите триггер текущей комнаты."
		return
	close()
	player._release_object()
	player.global_position = marker.global_position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()

func toggle_markers() -> void:
	if not debug_meshes.is_empty():
		for mesh in debug_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		debug_meshes.clear()
		return
	for marker in markers:
		for child in marker.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				var mesh := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = child.shape.size
				mesh.mesh = box
				var material := StandardMaterial3D.new()
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.albedo_color = Color(1, 0.8, 0.2, 0.2) if marker.transition_style == 1 else Color(0.2, 0.7, 1, 0.2)
				mesh.material_override = material
				marker.add_child(mesh)
				mesh.transform = child.transform
				debug_meshes.append(mesh)

func play_cutscene() -> void:
	if cutscenes.is_empty():
		status.text = "Нет зарегистрированных кат-сцен."
		return
	close()
	cutscenes[cutscene_picker.selected].play()

func restart_tutorial() -> void:
	get_tree().current_scene.find_child("Tutorial", true, false).restart()
	status.text = "Обучение начато заново."

func skip_tutorial() -> void:
	get_tree().current_scene.find_child("Tutorial", true, false).skip()
	status.text = "Обучение скрыто."
