extends CanvasLayer

## Temporary tools. Release exports always remove this UI.
const WEATHER_LABELS := ["Солнечно", "Тёплый вечер", "Пасмурно", "Гроза"]
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
var object_picker: OptionButton
var location_picker: OptionButton
var trigger_destination_picker: OptionButton
var cutscene_picker: OptionButton
var weather_picker: OptionButton
var weather_controller: Node
var locations: Array[Dictionary] = []
var cutscenes: Array[Node] = []
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
	_label(content, "ПАНЕЛЬ РАЗРАБОТЧИКА")
	_label(content, "Объекты перед камерой")
	object_picker = OptionButton.new()
	object_picker.fit_to_longest_item = false
	object_picker.add_item("Куб для обмена")
	object_picker.set_item_metadata(0, "swap_cube")
	object_picker.add_item("Сфера для обмена")
	object_picker.set_item_metadata(1, "swap_sphere")
	object_picker.add_item("Предмет для подбора")
	object_picker.set_item_metadata(2, "pickup_item")
	object_picker.add_item("Рычаг")
	object_picker.set_item_metadata(3, "lever")
	object_picker.add_item("Плита давления")
	object_picker.set_item_metadata(4, "weighted_plate")
	object_picker.add_item("Кнопка E")
	object_picker.set_item_metadata(5, "toggle_button")
	object_picker.select(0)
	content.add_child(object_picker)
	_button(content, "Создать объект", spawn_selected_object)
	selection_label = _label(content, "ЛКМ по созданному предмету — выбрать")
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.custom_minimum_size.x = 320
	delete_button = _button(content, "Удалить выбранный предмет", delete_selected)
	delete_button.disabled = true
	_button(content, "Удалить созданные объекты", clear_objects)
	_label(content, "Выбор погоды")
	weather_picker = OptionButton.new()
	weather_picker.fit_to_longest_item = false
	for weather_label in WEATHER_LABELS:
		weather_picker.add_item(weather_label)
	content.add_child(weather_picker)
	_button(content, "Применить погоду", apply_selected_weather)
	weather_controller = get_tree().current_scene.find_child("StreetWeather", true, false)
	if weather_controller != null and weather_controller.has_signal("weather_changed"):
		weather_controller.weather_changed.connect(_sync_weather_picker)
		_sync_weather_picker(int(weather_controller.get("mode")))
	else:
		weather_picker.disabled = true
	_label(content, "Перемещение по локациям")
	location_picker = OptionButton.new()
	location_picker.fit_to_longest_item = false
	content.add_child(location_picker)
	_button(content, "Перейти", teleport_to_selected_location)
	_label(content, "Установка триггера переноса")
	trigger_destination_picker = OptionButton.new()
	trigger_destination_picker.fit_to_longest_item = false
	content.add_child(trigger_destination_picker)
	_button(content, "Поставить триггер перед камерой", place_location_trigger)
	_label(content, "Кат-сцены")
	cutscene_picker = OptionButton.new()
	cutscene_picker.fit_to_longest_item = false
	content.add_child(cutscene_picker)
	_button(content, "Запустить выбранную кат-сцену", play_cutscene)
	_label(content, "Пробел — пропустить пролёт камеры")
	_label(content, "Обучение")
	_button(content, "Начать обучение заново", restart_tutorial)
	_button(content, "Скрыть обучение", skip_tutorial)
	_button(content, "Обновить списки локаций и кат-сцен", refresh)
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

func apply_selected_weather() -> void:
	if weather_controller == null or not is_instance_valid(weather_controller):
		status.text = "Контроллер погоды недоступен."
		return
	if player.has_meta("location_transition_active") or player.has_meta("cutscene_active") \
		or player.swap_in_progress or get_tree().paused:
		_sync_weather_picker(int(weather_controller.get("mode")))
		status.text = "Нельзя менять погоду во время перехода, кат-сцены или обмена."
		return
	var index := weather_picker.selected
	if index < 0 or index >= WEATHER_LABELS.size():
		return
	if not bool(weather_controller.call("set_weather", index)):
		_sync_weather_picker(int(weather_controller.get("mode")))
		status.text = "Не удалось применить режим погоды."
		return
	status.text = "Режим погоды: %s" % WEATHER_LABELS[index]

func _sync_weather_picker(mode: int) -> void:
	if is_instance_valid(weather_picker) and mode >= 0 and mode < weather_picker.item_count:
		weather_picker.select(mode)

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
		refresh()
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
	_refresh_location_list()
	cutscenes.clear()
	cutscene_picker.clear()
	for scene in get_tree().get_nodes_in_group("developer_cutscenes"):
		if scene.has_method("play"):
			cutscenes.append(scene)
			cutscene_picker.add_item(str(scene.name))
	cutscene_picker.disabled = cutscenes.is_empty()

func _refresh_location_list() -> void:
	locations.clear()
	location_picker.clear()
	trigger_destination_picker.clear()
	var scene := get_tree().current_scene
	var save_manager := get_node("/root/SaveManager")
	_add_location("Лаборатория — место появления", "laboratory", save_manager.initial_player_transform)
	var transition_arrival := scene.get_node_or_null("LocationTransition/LaboratoryArrival") as Node3D
	_add_marker_location("Комната переходов", "transition_room", transition_arrival)
	var checkpoint_names := [
		["Level1Checkpoint", "Лаборатория — комната 1"],
		["Level2Checkpoint", "Лаборатория — комната 2"],
		["Level3Checkpoint", "Лаборатория — комната 3"],
		["Level4Checkpoint", "Лаборатория — комната 4"],
		["PuzzleRoomCheckpoint", "Лаборатория — комната с плитой"],
	]
	for checkpoint_info in checkpoint_names:
		var checkpoint := scene.find_child(str(checkpoint_info[0]), true, false)
		var spawn: Node3D
		if checkpoint != null:
			spawn = checkpoint.get_node_or_null("SpawnPoint") as Node3D
		_add_marker_location(str(checkpoint_info[1]), "laboratory", spawn)
	_add_room_location(scene, "CityRoom", "Город", "city")
	_add_room_location(scene, "FlashbackRoom", "Город воспоминаний", "flashback")
	_add_room_location(scene, "ForestRoom", "Лес", "forest")
	_add_room_location(scene, "KitchenRoom", "Кухня", "kitchen")
	location_picker.disabled = locations.is_empty()
	trigger_destination_picker.disabled = locations.is_empty()
	if not locations.is_empty():
		location_picker.select(0)
		trigger_destination_picker.select(0)

func _add_room_location(scene: Node, room_name: String, title: String, location_id: String) -> void:
	var room := scene.find_child(room_name, true, false)
	if room == null:
		return
	var arrival := room.find_child("Arrival", true, false) as Node3D
	_add_marker_location(title, location_id, arrival)

func _add_marker_location(title: String, location_id: String, marker: Node3D) -> void:
	if marker != null:
		_add_location(title, location_id, marker.global_transform)

func _add_location(title: String, location_id: String, transform: Transform3D) -> void:
	locations.append({"title": title, "location_id": location_id, "transform": transform})
	location_picker.add_item(title)
	trigger_destination_picker.add_item(title)

func teleport_to_selected_location() -> void:
	if _location_action_blocked():
		status.text = "Нельзя перемещать игрока во время перехода, кат-сцены или обмена."
		return
	if location_picker.selected < 0 or location_picker.selected >= locations.size():
		status.text = "Выберите локацию для перехода."
		return
	var target: Dictionary = locations[location_picker.selected]
	_teleport_to_location(str(target.location_id), target.transform)
	status.text = "Игрок перемещён: %s." % target.title

func _teleport_to_location(location_id: String, destination: Transform3D) -> void:
	player._release_object()
	player._drop_item()
	player.e_hold_pending = false
	player.e_hold_elapsed = 0.0
	player._set_placement_mode(false)
	player.velocity = Vector3.ZERO
	player.clear_swap_selection()
	player.global_transform = destination
	player.camera_pivot.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	var save_manager := get_node("/root/SaveManager")
	save_manager.save_player_checkpoint(player, "developer_%s" % location_id, location_id, destination)
	save_manager.checkpoint_restored.emit(location_id)

func _location_action_blocked() -> bool:
	return get_tree().paused or player.has_meta("location_transition_active") \
		or player.has_meta("cutscene_active") or player.swap_in_progress

func place_location_trigger() -> void:
	if _location_action_blocked():
		status.text = "Нельзя ставить триггер во время перехода, кат-сцены или обмена."
		return
	if trigger_destination_picker.selected < 0 or trigger_destination_picker.selected >= locations.size():
		status.text = "Выберите назначение триггера."
		return
	objects = objects.filter(func(node): return is_instance_valid(node))
	if objects.size() >= 50:
		status.text = "Лимит 50 объектов и триггеров."
		return
	var selected_location: Dictionary = locations[trigger_destination_picker.selected]
	var trigger := preload("res://scenes/kitchen_transition_trigger.tscn").instantiate() as Area3D
	trigger.set("destination_location_id", str(selected_location.location_id))
	trigger.set("destination_transform", selected_location.transform)
	trigger.name = "DeveloperTrigger_%d" % (objects.size() + 1)
	get_tree().current_scene.add_child(trigger)
	trigger.global_transform = _get_trigger_placement_transform()
	objects.append(trigger)
	status.text = "Триггер создан: %s. Для удаления нажмите «Удалить созданные объекты»." % selected_location.title

func _get_trigger_placement_transform() -> Transform3D:
	var camera := player.camera_pivot.get_node("Camera3D") as Camera3D
	var ray_from := camera.global_position
	var ray_to := ray_from - camera.global_basis.z * 5.0
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var position := ray_from - camera.global_basis.z * 3.0
	if not hit.is_empty():
		position = hit.position + hit.normal * 0.65
	return Transform3D(Basis.IDENTITY, position)

func spawn_selected_object() -> void:
	if object_picker.selected < 0:
		return
	spawn_object_template(str(object_picker.get_item_metadata(object_picker.selected)))

func spawn_object(pickup: bool) -> Node3D:
	return spawn_object_template("pickup_item" if pickup else "swap_cube")

func spawn_object_template(template_id: String) -> Node3D:
	objects = objects.filter(func(node): return is_instance_valid(node))
	if objects.size() >= 50:
		status.text = "Лимит 50 объектов. Удалите созданные объекты."
		return null
	var camera: Camera3D = player.camera_pivot.get_node("Camera3D")
	var target := camera.global_position - camera.global_basis.z * 3.0
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target, 3, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		target = hit.position + hit.normal * 0.8
	var object: Node3D
	var shape: Shape3D
	match template_id:
		"pickup_item":
			object = preload("res://scenes/items/pickup_test_item.tscn").instantiate() as Node3D
			var pickup_shape := BoxShape3D.new()
			pickup_shape.size = Vector3(0.7, 0.7, 0.7)
			shape = pickup_shape
		"lever":
			object = preload("res://scenes/lever.tscn").instantiate() as Node3D
			var lever_shape := BoxShape3D.new()
			lever_shape.size = Vector3(0.9, 1.0, 0.6)
			shape = lever_shape
		"weighted_plate":
			object = preload("res://scenes/weighted_plate.tscn").instantiate() as Node3D
			var plate_shape := BoxShape3D.new()
			plate_shape.size = Vector3(1.2, 0.3, 1.2)
			shape = plate_shape
		"toggle_button":
			object = preload("res://scenes/e_toggle_button.tscn").instantiate() as Node3D
			var button_shape := BoxShape3D.new()
			button_shape.size = Vector3(0.8, 0.4, 0.8)
			shape = button_shape
		_:
			object = RigidBody3D.new()
			object.set_script(preload("res://scripts/physics_object.gd"))
			object.add_to_group("swappable")
			object.add_to_group("swapAble")
			if template_id == "swap_sphere":
				var mesh := MeshInstance3D.new()
				var sphere_mesh := SphereMesh.new()
				sphere_mesh.radius = 0.5
				sphere_mesh.height = 1.0
				mesh.mesh = sphere_mesh
				var sphere_shape := SphereShape3D.new()
				sphere_shape.radius = 0.5
				shape = sphere_shape
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.25, 0.7, 0.85)
				mesh.material_override = material
				object.add_child(mesh)
			else:
				object.add_child(preload("res://scenes/items/lab_box_visual.tscn").instantiate())
				var box_shape := BoxShape3D.new()
				box_shape.size = Vector3.ONE
				shape = box_shape
			var collision := CollisionShape3D.new()
			collision.shape = shape
			object.add_child(collision)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, target)
	query.collision_mask = 3
	if not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		status.text = "Недостаточно места. Посмотрите на свободный участок."
		object.free()
		return null
	object.name = "DeveloperObject_%d" % (objects.size() + 1)
	get_tree().current_scene.add_child(object)
	object.global_position = target
	objects.append(object)
	status.text = "%s создан. Всего: %d" % [object.name, objects.size()]
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
	var tutorial := get_tree().current_scene.find_child("Tutorial", true, false)
	if tutorial == null or not tutorial.has_method("complete"):
		status.text = "Не удалось скрыть обучение."
		return
	tutorial.complete()
	status.text = "Обучение скрыто."
