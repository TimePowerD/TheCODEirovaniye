extends CharacterBody3D

signal gameplay_action(action: StringName)
var tutorial_walk_distance := 0.0
var tutorial_sprint_distance := 0.0
var tutorial_look_distance := 0.0
var swap_error_remaining := 0.0
var weather_press_consumed := false
const SWAP_SPACE_ERROR := "Недостаточно свободного места для обмена"
const SWAP_ROOM_ERROR := "Обменивать объекты можно только в пределах одной комнаты"
const SwapSpaceCheck := preload("res://scripts/swap_space_check.gd")
const SwapMotionPlanner := preload("res://scripts/swap_motion_planner.gd")
var swap_error_text := SWAP_SPACE_ERROR
var swap_body_states: Array[Dictionary] = []
var swap_source_transforms: Array[Transform3D] = []
var swap_visual_states: Array[Dictionary] = []

@export var walk_speed: float = 5.0
@export var sprint_multiplier: float = 1.4
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var has_swap_technology: bool = true
@export var swap_duration: float = 1.0
@export var swap_shake_strength: float = 0.035
@export var grab_distance: float = 4.0
@export var hold_distance: float = 2.5
@export var hold_lift: float = 0.15
@export var hold_strength: float = 18.0
@export var hold_damping: float = 5.0
@export var hold_rotation_sensitivity: float = 0.018
@export var hold_rotation_max_speed: float = 2.5
@export var pickup_distance: float = 3.0
@export var throw_impulse: float = 6.0
@export var throw_lift: float = 0.12
@export var place_hold_duration: float = 0.25
@export_range(0.5, 10.0, 0.1) var placement_distance: float = 3.0
@export var held_item_scale_factor: float = 0.55
@export var animation_blend_time: float = 0.18

@onready var camera_pivot: Node3D = $CameraPivot
@onready var aim_ray: RayCast3D = $CameraPivot/Camera3D/CenterRay
@onready var footstep_sound: AudioStreamPlayer3D = $FootstepSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound
@onready var item_use_sound: AudioStreamPlayer3D = $ItemUseSound
@onready var throw_sound: AudioStreamPlayer3D = $ThrowSound
@onready var place_sound: AudioStreamPlayer3D = $PlaceSound
@onready var swap_sound: AudioStreamPlayer3D = $SwapSound
@onready var animation_player: AnimationPlayer = $ZombieModel/AnimationPlayer

var footstep_streams: Array[AudioStream] = [
	preload("res://assets/audio/final sounds/footstep_concrete_1.mp3"),
	preload("res://assets/audio/final sounds/footstep_concrete_2.mp3"),
	preload("res://assets/audio/final sounds/footstep_concrete_3.mp3"),
	preload("res://assets/audio/final sounds/footstep_concrete_4.mp3"),
	preload("res://assets/audio/final sounds/footstep_concrete_5.mp3"),
]
var footstep_timer: float = 0.0

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var hovered_target: Node3D
var selected_target: Node3D
var swap_cycle_index := 0
var suppressed_hover_outline: Node3D
var outline_states: Dictionary = {}
var hover_outline_material: ShaderMaterial
var selected_outline_material: ShaderMaterial
var swap_in_progress: bool = false
var held_object: RigidBody3D
var held_item: RigidBody3D
var held_item_parent: Node
var held_item_collision_layer: int
var held_item_collision_mask: int
var held_item_original_scale: Vector3 = Vector3.ONE
var hand_anchor: Node3D
var placement_preview: MeshInstance3D
var placement_mode: bool = false
var placement_valid: bool = false
var placement_position: Vector3 = Vector3.ZERO
var placement_normal: Vector3 = Vector3.UP
var placement_basis := Basis.IDENTITY
var placement_hint := "Наведите на свободную поверхность"
const PLACEMENT_GAP := 0.005
var interaction_hint: Label
var e_hold_pending: bool = false
var e_hold_elapsed: float = 0.0
var item_use_tween: Tween
var checkpoint_transform: Transform3D
var checkpoint_camera_rotation := Vector3.ZERO
var rotation_gizmo: Node3D
var rotation_axis_materials: Array[StandardMaterial3D] = []
var rotation_ring_points: Array[PackedVector3Array] = []
var rotation_mode: bool = false
var rotation_axis_index: int = -1
var rotation_speed: float = 0.0
var rotation_cursor_anchor: Vector2 = Vector2.ZERO

const ROTATION_AXIS_PICK_RADIUS := 26.0
var current_player_animation: StringName = &""

const IDLE_ANIMATION: StringName = &"idleAnim"
const WALK_ANIMATION: StringName = &"walkAnim"
const JUMP_ANIMATION: StringName = &"jumpAnim_001"
const FALL_RESPAWN_Y := -3.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	checkpoint_transform = global_transform
	get_node("/root/SaveManager").capture_scene_start(self)
	if not get_node("/root/SaveManager").restore_player(self):
		checkpoint_camera_rotation = camera_pivot.rotation
		get_node("/root/SaveManager").set_location("laboratory")
	collision_mask = 3
	platform_floor_layers = 1
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	aim_ray.collision_mask = 3
	aim_ray.add_exception(self)
	animation_player.get_animation(IDLE_ANIMATION).loop_mode = Animation.LOOP_LINEAR
	animation_player.get_animation(WALK_ANIMATION).loop_mode = Animation.LOOP_LINEAR
	_play_player_animation(IDLE_ANIMATION)

	var outline_shader: Shader = preload("res://scripts/swap_outline.gdshader")
	hover_outline_material = ShaderMaterial.new()
	hover_outline_material.shader = outline_shader
	hover_outline_material.set_shader_parameter("outline_color", Color(1.0, 0.78, 0.18, 1.0))

	selected_outline_material = ShaderMaterial.new()
	selected_outline_material.shader = outline_shader
	selected_outline_material.set_shader_parameter("outline_color", Color.WHITE)

	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	camera_pivot.get_node("Camera3D").add_child(hand_anchor)
	hand_anchor.position = Vector3(0.58, -0.36, -0.82)
	_build_placement_preview()
	_build_rotation_gizmo()
	_build_interaction_hint()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _get_rotation_target() != null and rotation_mode:
			_update_rotation_from_cursor(event.position)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			apply_look(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_swap_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_try_grab_object()
			else:
				_release_object()
	elif event is InputEventKey:
		if event.keycode == KEY_TAB and event.pressed and not event.echo:
			_cycle_swap_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE and event.pressed and not event.echo and selected_target != null:
			selected_target = null
			swap_cycle_index = 0
			_refresh_outlines()
			_update_interaction_hint()
		elif event.keycode == KEY_R:
			if not event.echo:
				_set_rotation_mode(event.pressed)
		elif event.keycode == KEY_E and not event.echo:
			if not event.pressed and weather_press_consumed:
				weather_press_consumed = false
				return
			if event.pressed:
				var button := _weather_button()
				if button != null:
					weather_press_consumed = true
					e_hold_pending = false
					button.get_parent().activate(int(button.get_meta("weather_mode")), self)
					get_viewport().set_input_as_handled()
					return
			if event.pressed:
				if held_item != null:
					if item_use_tween != null and item_use_tween.is_running():
						return
					e_hold_pending = true
					e_hold_elapsed = 0.0
				else:
					if not _try_interact():
						_try_pickup_item()
			elif e_hold_pending:
				e_hold_pending = false
				if placement_mode:
					_place_held_item()
				elif held_item != null:
					_use_held_item()
		elif event.pressed and not event.echo:
			if rotation_mode and event.keycode in [KEY_1, KEY_2, KEY_3]:
				_set_rotation_axis(event.keycode - KEY_1)
				rotation_cursor_anchor = get_viewport().get_mouse_position()
			elif event.keycode == KEY_Q and held_item != null:
				_throw_item()

func _weather_button() -> StaticBody3D:
	if get_tree().paused or swap_in_progress or has_meta("location_transition_active") or has_meta("cutscene_active") or has_meta("developer_tools_open"):
		return null
	var camera: Camera3D = camera_pivot.get_node("Camera3D")
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 3.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.is_in_group("weather_button"):
		var panel: Node = (hit.collider as StaticBody3D).get_parent()
		if panel.has_method("is_player_in_zone") and panel.is_player_in_zone(self):
			return hit.collider
	return null

func apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	camera_pivot.rotate_x(-relative.y * mouse_sensitivity)
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	tutorial_look_distance += relative.length()
	if tutorial_look_distance >= 80.0:
		tutorial_look_distance = 0.0
		gameplay_action.emit(&"look")

func _physics_process(delta: float) -> void:
	swap_error_remaining = maxf(0.0, swap_error_remaining - delta)
	if e_hold_pending and is_instance_valid(held_item) and Input.is_key_pressed(KEY_E):
		e_hold_elapsed += delta
		if e_hold_elapsed >= place_hold_duration and not placement_mode:
			_set_placement_mode(true)
	else:
		e_hold_elapsed = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
		jump_sound.play()
		gameplay_action.emit(&"jump")

	var input_2d := Vector2.ZERO
	input_2d.y -= float(Input.is_key_pressed(KEY_W))
	input_2d.y += float(Input.is_key_pressed(KEY_S))
	input_2d.x -= float(Input.is_key_pressed(KEY_A))
	input_2d.x += float(Input.is_key_pressed(KEY_D))
	input_2d = input_2d.normalized()

	var move_direction := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()
	var is_sprinting := Input.is_key_pressed(KEY_SHIFT)
	var speed := walk_speed * (sprint_multiplier if is_sprinting else 1.0)
	var target_horizontal_velocity := move_direction * speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var momentum_time := 0.2
	var acceleration := speed / momentum_time
	horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	var previous_position := global_position
	move_and_slide()
	if global_position.y < FALL_RESPAWN_Y:
		return_to_checkpoint()
		return
	if input_2d.length_squared() > 0.0:
		var traveled := Vector2(global_position.x - previous_position.x, global_position.z - previous_position.z).length()
		tutorial_walk_distance += traveled
		if Input.is_key_pressed(KEY_SHIFT):
			tutorial_sprint_distance += traveled
			if tutorial_sprint_distance >= 1.0:
				tutorial_sprint_distance = 0.0
				gameplay_action.emit(&"sprint")
		if tutorial_walk_distance >= 1.0:
			tutorial_walk_distance = 0.0
			gameplay_action.emit(&"walk")
	_update_footstep_sound(delta, is_on_floor() and not input_2d.is_zero_approx())
	if placement_mode:
		_update_placement_preview()
	_update_held_object()
	_update_held_rotation(delta)
	_update_rotation_gizmo()
	_update_player_animation(input_2d)
	_update_swap_highlight()
	_update_interaction_hint()

func _update_footstep_sound(delta: float, is_moving_on_floor: bool) -> void:
	if not is_moving_on_floor:
		footstep_timer = 0.0
		return

	footstep_timer -= delta
	if footstep_timer <= 0.0:
		var is_running := Input.is_key_pressed(KEY_SHIFT)
		footstep_sound.stream = footstep_streams.pick_random()
		footstep_sound.play()
		footstep_timer = 0.36 if is_running else 0.5

func _try_grab_object() -> void:
	if swap_in_progress or held_object != null or held_item != null or not aim_ray.is_colliding():
		return
	var collider := aim_ray.get_collider()
	if not collider is RigidBody3D:
		return
	var target := collider as RigidBody3D
	if target.has_meta("object_swap_locked"):
		return
	if not target.is_in_group("swapAble") or target.get("physics_enabled") != true:
		return
	if global_position.distance_to(target.global_position) > grab_distance:
		return
	held_object = target
	held_object.sleeping = false
	add_collision_exception_with(held_object)
	gameplay_action.emit(&"grab")

func _release_object() -> void:
	var was_holding := is_instance_valid(held_object)
	_set_rotation_mode(false)
	if is_instance_valid(held_object):
		remove_collision_exception_with(held_object)
	held_object = null
	if was_holding:
		gameplay_action.emit(&"release_grab")

func _try_pickup_item() -> void:
	if swap_in_progress or held_object != null or held_item != null or not aim_ray.is_colliding():
		return
	var collider := aim_ray.get_collider()
	if not collider is RigidBody3D:
		return
	var item := collider as RigidBody3D
	if item.has_meta("object_swap_locked"):
		return
	if not item.is_in_group("carryable"):
		return
	if global_position.distance_to(item.global_position) > pickup_distance:
		return
	_pick_up_item(item)

func _try_interact() -> bool:
	if not aim_ray.is_colliding():
		return false
	var target := aim_ray.get_collider() as Node
	if target == null or not target.is_in_group("interactable") or not target.has_method("interact"):
		return false
	target.call("interact", self)
	return true

func _use_held_item() -> void:
	if item_use_tween != null and item_use_tween.is_running():
		return
	if is_instance_valid(held_item) and held_item.has_method("use_item"):
		if held_item.get("can_use") == false:
			return
		held_item.call("use_item", self)
		item_use_sound.play()
		_play_item_use_animation()
		gameplay_action.emit(&"use")

func _play_item_use_animation() -> void:
	if not is_instance_valid(held_item):
		return
	if item_use_tween != null and item_use_tween.is_running():
		item_use_tween.kill()
	var start_position := held_item.position
	var start_rotation := held_item.rotation
	var action_position := start_position + Vector3(0.0, 0.07, -0.2)
	var action_rotation := start_rotation + Vector3(deg_to_rad(-16.0), deg_to_rad(10.0), deg_to_rad(-6.0))
	item_use_tween = create_tween()
	item_use_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	item_use_tween.tween_property(held_item, "position", action_position, 0.12)
	item_use_tween.parallel().tween_property(held_item, "rotation", action_rotation, 0.12)
	item_use_tween.set_ease(Tween.EASE_IN_OUT)
	item_use_tween.tween_property(held_item, "position", start_position, 0.18)
	item_use_tween.parallel().tween_property(held_item, "rotation", start_rotation, 0.18)

func _pick_up_item(item: RigidBody3D) -> void:
	# Also enforce the lock for calls from scripts, not only keyboard input.
	if swap_in_progress or held_object != null or held_item != null or not is_instance_valid(item):
		return
	if item.is_queued_for_deletion() or item.has_meta("object_swap_locked"):
		return
	held_item = item
	held_item_parent = item.get_parent()
	held_item_collision_layer = item.collision_layer
	held_item_collision_mask = item.collision_mask
	# Store world scale so reparenting to/from a scaled container cannot change
	# the volume that placement validation checks.
	held_item_original_scale = item.global_basis.get_scale()
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	item.reparent(hand_anchor, false)
	item.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	item.scale = held_item_original_scale * held_item_scale_factor
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	pickup_sound.play()
	gameplay_action.emit(&"pickup")

func _drop_item() -> void:
	if not is_instance_valid(held_item):
		_set_placement_mode(false)
		held_item = null
		return
	_release_held_item(hand_anchor.global_position - hand_anchor.global_basis.z * 0.45, held_item.global_basis, velocity)

func _throw_item() -> void:
	if not is_instance_valid(held_item):
		return
	var camera := camera_pivot.get_node("Camera3D") as Camera3D
	var forward := -camera.global_basis.z
	var item := _release_held_item(hand_anchor.global_position + forward * 0.35, held_item.global_basis, velocity)
	if item != null and not item.freeze:
		throw_sound.play()
		item.apply_central_impulse((forward + Vector3.UP * throw_lift).normalized() * throw_impulse)
		gameplay_action.emit(&"throw")

func _release_held_item(drop_position: Vector3, drop_basis: Basis, initial_velocity: Vector3) -> RigidBody3D:
	var item: RigidBody3D = held_item
	var parent := held_item_parent if is_instance_valid(held_item_parent) else get_tree().current_scene
	_set_rotation_mode(false)
	_set_placement_mode(false)
	if item_use_tween != null and item_use_tween.is_running():
		item_use_tween.kill()
	item.reparent(parent, true)
	item.global_transform = Transform3D(drop_basis.orthonormalized().scaled_local(held_item_original_scale), drop_position)
	item.collision_layer = held_item_collision_layer
	item.collision_mask = held_item_collision_mask
	item.freeze = item.get("physics_enabled") != true
	item.linear_velocity = initial_velocity
	item.angular_velocity = Vector3.ZERO
	held_item = null
	held_item_parent = null
	e_hold_pending = false
	e_hold_elapsed = 0.0
	return item

func _build_placement_preview() -> void:
	placement_preview = MeshInstance3D.new()
	placement_preview.name = "PlacementMarker"
	placement_preview.top_level = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	placement_preview.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.2, 1.0, 0.45, 0.65)
	placement_preview.material_override = material
	placement_preview.hide()
	hand_anchor.add_child(placement_preview)

func _build_interaction_hint() -> void:
	interaction_hint = Label.new()
	interaction_hint.name = "InteractionHint"
	interaction_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	interaction_hint.offset_left = -500.0
	interaction_hint.offset_right = -24.0
	interaction_hint.offset_top = -190.0
	interaction_hint.offset_bottom = -24.0
	interaction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	interaction_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interaction_hint.add_theme_font_size_override("font_size", 12)
	interaction_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.72))
	interaction_hint.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.027, 0.58))
	interaction_hint.add_theme_constant_override("outline_size", 3)
	interaction_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_hint.hide()
	var hud := get_node_or_null("../HUD") as CanvasLayer
	if hud != null:
		hud.call_deferred("add_child", interaction_hint)
	else:
		var fallback_hud := CanvasLayer.new()
		fallback_hud.name = "InteractionHUD"
		fallback_hud.call_deferred("add_child", interaction_hint)
		get_tree().current_scene.call_deferred("add_child", fallback_hud)

func _update_interaction_hint() -> void:
	if not is_instance_valid(interaction_hint):
		return
	var weather_button := _weather_button()
	if weather_button != null:
		var title: String = weather_button.get_parent().TITLES[int(weather_button.get_meta("weather_mode"))]
		interaction_hint.text = "E — " + title
		interaction_hint.show()
		return
	if swap_in_progress:
		interaction_hint.text = "Выполняется обмен…\nЗахват, подбор и вращение временно недоступны"
		interaction_hint.show()
		return
	if swap_error_remaining > 0.0:
		interaction_hint.text = swap_error_text
		interaction_hint.show()
		return
	var hint_text := ""
	if placement_mode:
		hint_text = ("Отпустите E — разместить" if placement_valid else placement_hint) + "\nQ — бросить\nR + мышь — вращать"
	elif rotation_mode and _get_rotation_target() != null:
		if held_item != null:
			hint_text = "Наведите на кольцо\nДвигайте поперёк — вращать\n1/2/3 — выбрать ось\nE — использовать/разместить\nQ — бросить\nОтпустите R — выйти"
		else:
			hint_text = "Наведите на кольцо\nДвигайте поперёк — вращать\n1/2/3 — ось X/Y/Z\nОтпустите R — выйти"
	elif held_item != null:
		hint_text = "E — использовать\nУдерживайте E — выбрать место\nОтпустите E — разместить\nQ — бросить\nR + мышь — вращать\n1/2/3 — выбрать ось"
	elif held_object != null:
		hint_text = "Удерживайте ПКМ — перемещать\nR — вращение по кольцам\n1/2/3 — ось X/Y/Z\nОтпустите ПКМ — бросить"
	elif aim_ray.is_colliding():
		var collider := aim_ray.get_collider()
		if collider is Node3D:
			var target := collider as Node3D
			if target.is_in_group("interactable"):
				if target.get("is_weight_plate") == true:
					hint_text = "Плита: нажмите весом\nМинимум: %.0f кг" % float(target.get("minimum_weight"))
				elif target.get("is_active") == true:
					hint_text = "E — деактивировать"
				else:
					hint_text = "E — активировать"
			elif target.is_in_group("carryable"):
				hint_text = "E — взять в руки\nПКМ — перемещать\nR — вращать"
			elif target.is_in_group("swapAble"):
				if target.is_in_group("swappable"):
					hint_text = "ЛКМ — выбрать для обмена\nПКМ — перемещать\nR — вращать"
				else:
					hint_text = "ПКМ — перемещать\nR — вращать"
	if selected_target != null:
		hint_text += "\nTab — обменять с ближайшим объектом комнаты · Backspace — отменить"
	elif has_swap_technology:
		hint_text += "\nTab — выбрать объект для обмена"
	interaction_hint.text = hint_text
	interaction_hint.visible = not hint_text.is_empty()

func _set_placement_mode(active: bool) -> void:
	placement_mode = active and is_instance_valid(held_item)
	placement_valid = false
	if is_instance_valid(placement_preview):
		placement_preview.visible = placement_mode
	if placement_mode:
		_update_placement_preview()

func _update_placement_preview() -> void:
	placement_valid = false
	placement_preview.hide()
	if not is_instance_valid(held_item):
		return
	aim_ray.force_raycast_update()
	if not aim_ray.is_colliding():
		placement_hint = "Наведите на свободную поверхность"
		return
	var camera: Camera3D = camera_pivot.get_node("Camera3D")
	var surface_point := aim_ray.get_collision_point()
	if camera.global_position.distance_to(surface_point) > placement_distance:
		placement_hint = "Слишком далеко: размещение не дальше %.1f м" % placement_distance
		return
	placement_normal = aim_ray.get_collision_normal().normalized()
	if placement_normal.length_squared() < 0.9:
		placement_hint = "Недопустимая поверхность"
		return
	placement_basis = Basis(Quaternion(Vector3.UP, placement_normal)) * held_item.global_basis.orthonormalized()
	var surface_offset := _get_item_surface_offset(held_item, placement_basis, placement_normal)
	placement_position = surface_point + placement_normal * (surface_offset + PLACEMENT_GAP)
	if camera.global_position.distance_to(placement_position) > placement_distance:
		placement_hint = "Предмет окажется слишком далеко"
		return
	var future := Transform3D(placement_basis.scaled_local(held_item_original_scale), placement_position)
	if not SwapSpaceCheck.can_place(held_item, future):
		placement_hint = "Недостаточно свободного места для предмета"
		return
	placement_valid = true
	placement_preview.global_position = surface_point + placement_normal * 0.025
	placement_preview.show()

func _place_held_item() -> bool:
	# Never trust a cached green marker after the player or an obstacle moves.
	_update_placement_preview()
	if not placement_valid:
		_update_interaction_hint()
		return false
	var item := _release_held_item(placement_position, placement_basis, Vector3.ZERO)
	if item != null:
		place_sound.play()
		gameplay_action.emit(&"place")
		return true
	return false

func _get_item_surface_offset(item: RigidBody3D, item_basis: Basis, surface_normal: Vector3) -> float:
	var offset := 0.0
	var future_basis := item_basis.scaled_local(held_item_original_scale)
	for owner_id in item.get_shape_owners():
		if item.is_shape_owner_disabled(owner_id):
			continue
		var shape_transform := Transform3D(future_basis, Vector3.ZERO) * item.shape_owner_get_transform(owner_id)
		var normal := shape_transform.basis.transposed() * surface_normal
		for index in range(item.shape_owner_get_shape_count(owner_id)):
			var shape := item.shape_owner_get_shape(owner_id, index)
			var extent := 0.0
			if shape is BoxShape3D:
				extent = shape.size.dot(normal.abs()) * 0.5
			elif shape is SphereShape3D:
				extent = shape.radius * normal.length()
			elif shape is CylinderShape3D:
				extent = shape.height * absf(normal.y) * 0.5 + shape.radius * Vector2(normal.x, normal.z).length()
			elif shape is CapsuleShape3D:
				extent = shape.radius * normal.length() + maxf(shape.height * 0.5 - shape.radius, 0.0) * absf(normal.y)
			elif shape is ConvexPolygonShape3D:
				for point in shape.points:
					extent = maxf(extent, -point.dot(normal))
			offset = maxf(offset, extent - surface_normal.dot(shape_transform.origin))
	return offset

func return_to_checkpoint() -> void:
	_release_object()
	_drop_item()
	get_node("/root/SaveManager").reset_world_to_initial()
	global_transform = checkpoint_transform
	camera_pivot.rotation = checkpoint_camera_rotation
	velocity = Vector3.ZERO
	reset_interaction_modes()
	reset_physics_interpolation()
	gameplay_action.emit(&"checkpoint")

func _update_held_object() -> void:
	if not is_instance_valid(held_object):
		held_object = null
		return
	if swap_in_progress or held_object.has_meta("object_swap_locked"):
		_release_object()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_release_object()
		return
	var camera := camera_pivot.get_node("Camera3D") as Camera3D
	var hold_point := camera.global_position - camera.global_basis.z * hold_distance + Vector3.UP * hold_lift
	var mass_factor := 1.0 / sqrt(maxf(held_object.mass, 0.1))
	var stiffness := hold_strength * mass_factor
	var damping := hold_damping * mass_factor
	var acceleration := (hold_point - held_object.global_position) * stiffness - held_object.linear_velocity * damping
	held_object.apply_central_force(acceleration * held_object.mass)

func _update_held_rotation(delta: float) -> void:
	if swap_in_progress:
		return
	var target := _get_rotation_target()
	if not rotation_mode or rotation_axis_index < 0 or target == null:
		return
	if target.has_meta("object_swap_locked"):
		return
	var rotation_axis := _get_rotation_axis()
	if target == held_item:
		var rotation_delta := Basis(Quaternion(rotation_axis, rotation_speed * delta))
		target.global_basis = rotation_delta * target.global_basis
	else:
		target.angular_velocity = rotation_axis * rotation_speed
	if absf(rotation_speed) > 0.01 and delta > 0.0:
		gameplay_action.emit(&"rotate")

func _get_rotation_target() -> RigidBody3D:
	if is_instance_valid(held_object):
		return held_object
	if is_instance_valid(held_item):
		return held_item
	return null

func _build_rotation_gizmo() -> void:
	rotation_gizmo = Node3D.new()
	rotation_gizmo.name = "RotationAxes"
	get_tree().current_scene.call_deferred("add_child", rotation_gizmo)
	rotation_gizmo.hide()
	for axis_index in range(3):
		var points := PackedVector3Array()
		for step in range(65):
			var angle := TAU * float(step) / 64.0
			var ring_point: Vector3
			if axis_index == 0:
				ring_point = Vector3(0.0, cos(angle), sin(angle)) * 1.35
			elif axis_index == 1:
				ring_point = Vector3(cos(angle), 0.0, sin(angle)) * 1.35
			else:
				ring_point = Vector3(cos(angle), sin(angle), 0.0) * 1.35
			points.append(ring_point)
		rotation_ring_points.append(points)

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = [Color(1.0, 0.22, 0.18), Color(0.25, 1.0, 0.35), Color(0.2, 0.55, 1.0)][axis_index]
		rotation_axis_materials.append(material)

		var ring_mesh := ImmediateMesh.new()
		ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for point in points:
			ring_mesh.surface_add_vertex(point)
		ring_mesh.surface_end()
		var ring_instance := MeshInstance3D.new()
		ring_instance.name = ["RingX", "RingY", "RingZ"][axis_index]
		ring_instance.mesh = ring_mesh
		rotation_gizmo.add_child(ring_instance)

func reset_interaction_modes() -> void:
	weather_press_consumed = false
	# Releases may happen while gameplay input is paused and never reach us.
	# Keep the carried item, but require a fresh press for rotation/placement.
	_set_rotation_mode(false)
	e_hold_pending = false
	e_hold_elapsed = 0.0
	_set_placement_mode(false)

func clear_swap_selection() -> void:
	selected_target = null
	swap_cycle_index = 0
	hovered_target = null
	suppressed_hover_outline = null
	_refresh_outlines()

func _set_rotation_mode(active: bool) -> void:
	if active and swap_in_progress:
		return
	if active and _get_rotation_target() == null:
		return
	if active and _get_rotation_target().has_meta("object_swap_locked"):
		return
	rotation_mode = active
	rotation_axis_index = -1
	rotation_speed = 0.0
	if is_instance_valid(held_object):
		held_object.angular_velocity = Vector3.ZERO
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(rotation_gizmo):
		rotation_gizmo.visible = active and _get_rotation_target() != null
	_set_rotation_axis(-1)

func _set_rotation_axis(axis_index: int) -> void:
	rotation_axis_index = axis_index
	for index in range(rotation_axis_materials.size()):
		var material := rotation_axis_materials[index]
		var base_color: Color = [Color(1.0, 0.22, 0.18), Color(0.25, 1.0, 0.35), Color(0.2, 0.55, 1.0)][index]
		material.albedo_color = Color(1.0, 0.88, 0.2) if index == axis_index else base_color

func _get_rotation_axis() -> Vector3:
	var target := _get_rotation_target()
	if target == null:
		return Vector3.ZERO
	match rotation_axis_index:
		0:
			return target.global_basis.x.normalized()
		1:
			return target.global_basis.y.normalized()
		2:
			return target.global_basis.z.normalized()
	return Vector3.ZERO

func _update_rotation_gizmo() -> void:
	if not is_instance_valid(rotation_gizmo):
		return
	var target := _get_rotation_target()
	if target == null:
		rotation_gizmo.hide()
		return
	if rotation_mode:
		rotation_gizmo.global_transform = Transform3D(target.global_basis, target.global_position)

func _update_rotation_from_cursor(mouse_position: Vector2) -> void:
	var target := _get_rotation_target()
	var hovered_axis := _find_rotation_axis(mouse_position)
	if hovered_axis >= 0 and hovered_axis != rotation_axis_index:
		_set_rotation_axis(hovered_axis)
		rotation_cursor_anchor = mouse_position
		rotation_speed = 0.0
	if rotation_axis_index < 0 or target == null:
		return

	var camera := camera_pivot.get_node("Camera3D") as Camera3D
	var axis := _get_rotation_axis()
	var screen_center := camera.unproject_position(target.global_position)
	var screen_axis := camera.unproject_position(target.global_position + axis) - screen_center
	if screen_axis.length_squared() < 0.001:
		screen_axis = Vector2.RIGHT
	screen_axis = screen_axis.normalized()
	var perpendicular := Vector2(-screen_axis.y, screen_axis.x)
	var sideways_offset := (mouse_position - rotation_cursor_anchor).dot(perpendicular)
	rotation_speed = clampf(sideways_offset * hold_rotation_sensitivity, -hold_rotation_max_speed, hold_rotation_max_speed)

func _find_rotation_axis(mouse_position: Vector2) -> int:
	var target := _get_rotation_target()
	if not is_instance_valid(rotation_gizmo) or target == null:
		return -1
	var camera := camera_pivot.get_node("Camera3D") as Camera3D
	var closest_axis := -1
	var closest_distance := ROTATION_AXIS_PICK_RADIUS
	for axis_index in range(rotation_ring_points.size()):
		var points: PackedVector3Array = rotation_ring_points[axis_index]
		for point_index in range(points.size() - 1):
			var world_start := rotation_gizmo.to_global(points[point_index])
			var world_end := rotation_gizmo.to_global(points[point_index + 1])
			if camera.is_position_behind(world_start) and camera.is_position_behind(world_end):
				continue
			var screen_start := camera.unproject_position(world_start)
			var screen_end := camera.unproject_position(world_end)
			var distance := _distance_to_screen_segment(mouse_position, screen_start, screen_end)
			if distance < closest_distance:
				closest_distance = distance
				closest_axis = axis_index
	return closest_axis

func _distance_to_screen_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() < 0.001:
		return point.distance_to(start)
	var along := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * along)

func _update_player_animation(input_2d: Vector2) -> void:
	if not is_on_floor():
		_play_player_animation(JUMP_ANIMATION)
	elif input_2d.length_squared() > 0.0:
		_play_player_animation(WALK_ANIMATION)
	else:
		_play_player_animation(IDLE_ANIMATION)

func _play_player_animation(animation_name: StringName) -> void:
	if current_player_animation == animation_name:
		return
	current_player_animation = animation_name
	animation_player.play(animation_name, animation_blend_time)

func _handle_swap_click() -> void:
	if not has_swap_technology or swap_in_progress or held_object != null or held_item != null or not is_instance_valid(hovered_target):
		return
	if not hovered_target.is_in_group("swappable"):
		return
	if selected_target != null and not is_instance_valid(selected_target):
		selected_target = null
	if selected_target == null:
		selected_target = hovered_target
		gameplay_action.emit(&"select_swap")
		suppressed_hover_outline = null
	elif selected_target != hovered_target:
		if _start_swap(selected_target, hovered_target):
			selected_target = null
			swap_cycle_index = 0
	_refresh_outlines()
	_update_interaction_hint()

func _cycle_swap_selection() -> void:
	if not has_swap_technology or swap_in_progress or held_object != null or held_item != null:
		return
	if selected_target != null and not is_instance_valid(selected_target):
		selected_target = null
		swap_cycle_index = 0
	var current_room := _room_anchor_for_position(global_position)
	var candidates: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("swappable"):
		if not candidate is Node3D or candidate == selected_target or not is_instance_valid(candidate):
			continue
		if candidate.get("physics_enabled") != true or candidate.has_meta("object_swap_locked"):
			continue
		if _room_anchor_for_position(candidate.global_position) != current_room:
			continue
		candidates.append(candidate)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)
	if candidates.is_empty():
		swap_error_text = "В этой комнате нет доступной пары для обмена"
		swap_error_remaining = 1.5
		_update_interaction_hint()
		return
	if selected_target == null:
		selected_target = candidates[0]
		swap_cycle_index = 0
		gameplay_action.emit(&"select_swap")
	else:
		var candidate := candidates[swap_cycle_index % candidates.size()]
		swap_cycle_index = (swap_cycle_index + 1) % candidates.size()
		if _start_swap(selected_target, candidate):
			selected_target = null
			swap_cycle_index = 0
	_refresh_outlines()
	_update_interaction_hint()

func _room_anchor_for_position(position: Vector3) -> Node3D:
	var closest: Node3D
	var closest_distance := INF
	for anchor in get_tree().get_nodes_in_group("swap_room_anchor"):
		if not anchor is Node3D or not is_instance_valid(anchor):
			continue
		var offset: Vector3 = anchor.global_position - position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < closest_distance:
			closest_distance = distance
			closest = anchor
	return closest

func _start_swap(first: Node3D, second: Node3D) -> bool:
	if swap_in_progress or held_object != null or held_item != null:
		return false
	if not is_instance_valid(first) or not is_instance_valid(second):
		return false
	if first == second:
		return false
	if first.has_meta("object_swap_locked") or second.has_meta("object_swap_locked"):
		return false
	var player_room := _room_anchor_for_position(global_position)
	if player_room == null \
		or _room_anchor_for_position(first.global_position) != player_room \
		or _room_anchor_for_position(second.global_position) != player_room:
		swap_error_text = SWAP_ROOM_ERROR
		swap_error_remaining = 1.5
		_update_interaction_hint()
		return false
	var plan := SwapMotionPlanner.create_plan(first, second, first.global_transform, second.global_transform)
	if not plan.ok:
		swap_error_text = "%s: %s" % [SWAP_SPACE_ERROR, plan.reason]
		swap_error_remaining = 1.5
		_update_interaction_hint()
		return false
	swap_error_remaining = 0.0
	swap_in_progress = true
	swap_source_transforms.assign([first.global_transform, second.global_transform])
	for target in [first, second]:
		var state := {"target": target, "transform": target.global_transform}
		target.set_meta("object_swap_locked", true)
		if target is RigidBody3D:
			state["freeze"] = target.freeze
			state["linear_velocity"] = target.linear_velocity
			state["angular_velocity"] = target.angular_velocity
			target.freeze = true
		swap_body_states.append(state)
		for mesh in _get_target_meshes(target):
			if _can_animate_swap_mesh(mesh):
				swap_visual_states.append({"mesh": mesh, "position": mesh.position, "direction": 1.0 if target == first else -1.0})
	var first_start := first.global_position
	var second_start := second.global_position
	var tween := create_tween()
	var update_motion := Callable(self, "_update_swap_motion")
	tween.tween_method(update_motion, 0.0, 1.0, maxf(swap_duration, 0.01))
	tween.finished.connect(_complete_swap.bind(first, second, first_start, second_start))
	return true

func _update_swap_motion(progress: float) -> void:
	var shake_envelope := sin(progress * PI)
	var shake_phase := progress * TAU * 8.0
	var shake_offset := Vector3(
		sin(shake_phase),
		cos(shake_phase * 0.83),
		sin(shake_phase * 1.17)
	) * swap_shake_strength * shake_envelope
	# Shake visuals only: frozen colliders must not nudge neighbors or the floor.
	for visual in swap_visual_states:
		var mesh = visual.mesh
		if is_instance_valid(mesh):
			mesh.position = visual.position + mesh.get_parent().global_basis.inverse() * shake_offset * visual.direction

func _complete_swap(first: Node3D, second: Node3D, first_start: Vector3, second_start: Vector3) -> void:
	for visual in swap_visual_states:
		if is_instance_valid(visual.mesh):
			visual.mesh.position = visual.position
	swap_visual_states.clear()
	var plan := SwapMotionPlanner.create_plan(first, second, swap_source_transforms[0], swap_source_transforms[1])
	var success: bool = plan.ok
	if success:
		for push in plan.pushes:
			var body: RigidBody3D = push.body
			body.global_transform = push.transform
			body.sleeping = false
			body.reset_physics_interpolation()
		first.global_transform = plan.first
		second.global_transform = plan.second
		_spawn_swap_puff(first_start)
		_spawn_swap_puff(second_start)
		swap_sound.play()
		gameplay_action.emit(&"swap")

		_animate_swap_visuals(first)
		_animate_swap_visuals(second)
	else:
		swap_error_text = "%s: %s" % [SWAP_SPACE_ERROR, plan.reason]
		swap_error_remaining = 1.5
		if is_instance_valid(first):
			selected_target = first
	for state in swap_body_states:
		var target = state.target
		if not is_instance_valid(target):
			continue
		if not success:
			target.global_transform = state.transform
		target.remove_meta("object_swap_locked")
		if target is RigidBody3D:
			target.freeze = state.freeze
			target.linear_velocity = Vector3.ZERO if success else state.linear_velocity
			target.angular_velocity = Vector3.ZERO if success else state.angular_velocity
	swap_body_states.clear()
	swap_source_transforms.clear()
	swap_in_progress = false
	_refresh_outlines()
	_update_interaction_hint()

func _can_animate_swap_mesh(mesh: MeshInstance3D) -> bool:
	return mesh.find_children("*", "CollisionShape3D", true, false).is_empty() and mesh.find_children("*", "CollisionPolygon3D", true, false).is_empty() and mesh.find_children("*", "CollisionObject3D", true, false).is_empty()

func _animate_swap_visuals(target: Node3D) -> void:
	# Animate only render meshes: the checked physics volume stays full-size.
	for mesh in _get_target_meshes(target):
		if not _can_animate_swap_mesh(mesh):
			continue
		var original_scale := mesh.scale
		mesh.scale = original_scale * 0.12
		create_tween().tween_property(mesh, "scale", original_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_swap_puff(effect_position: Vector3) -> void:
	var puff := CPUParticles3D.new()
	puff.amount = 20
	puff.lifetime = 0.2
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.08
	puff.direction = Vector3.UP
	puff.spread = 180.0
	puff.initial_velocity_min = 10.3
	puff.initial_velocity_max = 13.7
	puff.gravity = Vector3(0.0, 0.2, 0.0)
	puff.scale_amount_min = 0.7
	puff.scale_amount_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(0.94, 0.96, 1.0, 0.72))
	fade.set_color(1, Color(0.94, 0.96, 1.0, 0.0))
	puff.color_ramp = fade
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.06
	puff_mesh.height = 0.12
	var puff_material := StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.albedo_color = Color.WHITE
	puff_mesh.material = puff_material
	puff.mesh = puff_mesh
	get_tree().current_scene.add_child(puff)
	puff.global_position = effect_position
	puff.restart()
	get_tree().create_timer(puff.lifetime + 0.1).timeout.connect(puff.queue_free)

func _update_swap_highlight() -> void:
	if has_meta("developer_tools_open"):
		return
	aim_ray.force_raycast_update()
	var next_target: Node3D
	if aim_ray.is_colliding():
		var collider := aim_ray.get_collider()
		if collider is Node3D:
			var target: Node3D = collider
			if target.is_in_group("swappable"):
				next_target = target
	if suppressed_hover_outline != null and next_target != suppressed_hover_outline:
		suppressed_hover_outline = null
	hovered_target = next_target
	if selected_target != null and not is_instance_valid(selected_target):
		selected_target = null
	_refresh_outlines()

func _refresh_outlines() -> void:
	var desired_meshes: Dictionary = {}
	for target in [hovered_target, selected_target]:
		if target == null or target == suppressed_hover_outline or not is_instance_valid(target):
			continue
		var outline_material := selected_outline_material if target == selected_target else hover_outline_material
		for mesh in _get_target_meshes(target):
			desired_meshes[mesh.get_instance_id()] = {
				"mesh": mesh,
				"material": outline_material,
			}

	for mesh_id in outline_states.keys():
		if not desired_meshes.has(mesh_id):
			var old_state: Dictionary = outline_states[mesh_id]
			var old_mesh: MeshInstance3D = old_state["mesh"] as MeshInstance3D
			if is_instance_valid(old_mesh):
				old_mesh.material_overlay = old_state["previous_overlay"] as Material
			outline_states.erase(mesh_id)

	for mesh_id in desired_meshes:
		var desired_state: Dictionary = desired_meshes[mesh_id]
		var mesh: MeshInstance3D = desired_state["mesh"] as MeshInstance3D
		var material: Material = desired_state["material"] as Material
		if outline_states.has(mesh_id):
			var existing_state: Dictionary = outline_states[mesh_id]
			if existing_state["material"] != material:
				mesh.material_overlay = material
				existing_state["material"] = material
				outline_states[mesh_id] = existing_state
			continue
		outline_states[mesh_id] = {
			"mesh": mesh,
			"previous_overlay": mesh.material_overlay,
			"material": material,
		}
		mesh.material_overlay = material

func _get_target_meshes(target: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if target is MeshInstance3D:
		meshes.append(target)
	for child in target.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes
