extends Node3D

@export var player_path: NodePath = NodePath("../Player")
@export var animation_name: StringName = &"idle"
@export var head_bone_name: StringName = &"Head"
@export var max_yaw_degrees: float = 100.0
@export var max_pitch_degrees: float = 40.0
@export var room_manager_enabled: bool = true
@export_range(1, 32, 1) var room_count: int = 5
@export var room_step: Vector3 = Vector3(-18.0, 0.0, 0.0)
@export_range(0, 4, 1) var active_room_radius: int = 1
@export_range(0.1, 5.0, 0.1) var room_refresh_interval: float = 0.5

const PLAYER_LOOK_HEIGHT := 1.3

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var player: Node3D = get_node_or_null(player_path) as Node3D

var look_at_modifier: LookAtModifier3D
var look_target: Marker3D
var room_scientists: Dictionary[int, Node3D] = {}
var refresh_timer: float = 0.0
var scientist_active: bool = true
var room_anchor_transform: Transform3D


func _ready() -> void:
	room_anchor_transform = transform
	_start_idle_animation()
	_setup_head_tracking()

	if room_manager_enabled and is_instance_valid(player):
		_refresh_room_scientists()


func _process(delta: float) -> void:
	if room_manager_enabled:
		refresh_timer -= delta
		if refresh_timer <= 0.0:
			refresh_timer = room_refresh_interval
			_refresh_room_scientists()

	if not scientist_active:
		return
	if is_instance_valid(player) and is_instance_valid(look_target):
		look_target.global_position = player.global_position + Vector3.UP * PLAYER_LOOK_HEIGHT


func _start_idle_animation() -> void:
	if animation_player.has_animation(animation_name):
		var idle_animation: Animation = animation_player.get_animation(animation_name)
		idle_animation.loop_mode = Animation.LOOP_LINEAR
		animation_player.play(animation_name)
	else:
		push_warning("Scientist: animation '%s' was not found." % animation_name)


func _setup_head_tracking() -> void:
	var resolved_head_bone := _find_head_bone()
	if resolved_head_bone.is_empty():
		push_warning("Scientist: head bone was not found; idle animation will still play.")
		return

	head_bone_name = resolved_head_bone
	if not is_instance_valid(player):
		push_warning("Scientist: player target was not found.")
		return

	look_target = Marker3D.new()
	look_target.name = "ScientistLookTarget"
	look_target.top_level = true
	add_child(look_target)
	look_target.global_position = player.global_position + Vector3.UP * PLAYER_LOOK_HEIGHT

	look_at_modifier = LookAtModifier3D.new()
	look_at_modifier.name = "HeadLookAt"
	look_at_modifier.bone_name = String(head_bone_name)
	look_at_modifier.influence = 1.0
	look_at_modifier.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look_at_modifier.relative = true
	look_at_modifier.duration = 0.2
	look_at_modifier.use_angle_limitation = true
	look_at_modifier.symmetry_limitation = true
	look_at_modifier.primary_rotation_axis = Vector3.AXIS_Y
	look_at_modifier.primary_limit_angle = deg_to_rad(max_yaw_degrees)
	look_at_modifier.use_secondary_rotation = true
	look_at_modifier.secondary_limit_angle = deg_to_rad(max_pitch_degrees)
	skeleton.add_child(look_at_modifier)
	look_at_modifier.target_node = look_at_modifier.get_path_to(look_target)


func _refresh_room_scientists() -> void:
	if room_count <= 0 or room_step.length_squared() < 0.001 or not is_instance_valid(player):
		return

	var step_direction := room_step.normalized()
	var player_progress := (player.global_position - room_anchor_transform.origin).dot(step_direction) / room_step.length()
	var nearest_room := clampi(roundi(player_progress), 0, room_count - 1)

	for room_index in range(room_count):
		var should_be_active: bool = abs(room_index - nearest_room) <= active_room_radius
		if room_index == 0:
			_set_scientist_active(should_be_active)
			continue

		var room_scientist := room_scientists.get(room_index) as Node3D
		if should_be_active and not is_instance_valid(room_scientist):
			room_scientist = _create_room_scientist(room_index)
			if is_instance_valid(room_scientist):
				room_scientists[room_index] = room_scientist
		elif not should_be_active and is_instance_valid(room_scientist):
			room_scientist.queue_free()
			room_scientists.erase(room_index)


func _create_room_scientist(room_index: int) -> Node3D:
	var model_scene := load("res://assets/materials/animations/scientist.glb") as PackedScene
	if model_scene == null:
		push_warning("Scientist: source model could not be loaded.")
		return null

	var instance := model_scene.instantiate() as Node3D
	if instance == null:
		push_warning("Scientist: source model root is not Node3D.")
		return null

	instance.set_script(get_script())
	instance.set("room_manager_enabled", false)
	instance.transform = room_anchor_transform
	instance.transform.origin += room_step * room_index
	get_parent().call_deferred("add_child", instance)
	return instance


func _set_scientist_active(active: bool) -> void:
	if scientist_active == active:
		return
	scientist_active = active
	visible = active
	if is_instance_valid(look_at_modifier):
		look_at_modifier.active = active
	if not is_instance_valid(animation_player):
		return
	if active:
		if not animation_player.is_playing():
			animation_player.play(animation_name)
	else:
		animation_player.stop()


func _find_head_bone() -> StringName:
	var neck_fallback: StringName = &""
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := StringName(skeleton.get_bone_name(bone_index))
		var normalized_name := String(bone_name).to_lower()
		if normalized_name == "head" or normalized_name.ends_with("head"):
			return bone_name
		if neck_fallback.is_empty() and normalized_name.contains("neck"):
			neck_fallback = bone_name
	return neck_fallback
