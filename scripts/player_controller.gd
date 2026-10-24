extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_multiplier: float = 1.4
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var has_swap_technology: bool = true
@export var swap_duration: float = 1.0
@export var swap_shake_strength: float = 0.035

@onready var camera_pivot: Node3D = $CameraPivot
@onready var aim_ray: RayCast3D = $CameraPivot/Camera3D/CenterRay

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var hovered_target: Node3D
var selected_target: Node3D
var suppressed_hover_outline: Node3D
var outline_states: Dictionary = {}
var hover_outline_material: ShaderMaterial
var selected_outline_material: ShaderMaterial
var swap_in_progress: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	aim_ray.add_exception(self)

	var outline_shader: Shader = preload("res://scripts/swap_outline.gdshader")
	hover_outline_material = ShaderMaterial.new()
	hover_outline_material.shader = outline_shader
	hover_outline_material.set_shader_parameter("outline_color", Color(1.0, 0.78, 0.18, 1.0))

	selected_outline_material = ShaderMaterial.new()
	selected_outline_material.shader = outline_shader
	selected_outline_material.set_shader_parameter("outline_color", Color.WHITE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_swap_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and selected_target != null:
			if hovered_target == selected_target:
				suppressed_hover_outline = selected_target
			selected_target = null
			_refresh_outlines()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_2d := Vector2.ZERO
	input_2d.y -= float(Input.is_key_pressed(KEY_W))
	input_2d.y += float(Input.is_key_pressed(KEY_S))
	input_2d.x -= float(Input.is_key_pressed(KEY_A))
	input_2d.x += float(Input.is_key_pressed(KEY_D))
	input_2d = input_2d.normalized()

	var move_direction := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()
	var speed := walk_speed * (sprint_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var target_horizontal_velocity := move_direction * speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var momentum_time := 0.2
	var acceleration := speed / momentum_time
	horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	_update_swap_highlight()

func _handle_swap_click() -> void:
	if not has_swap_technology or swap_in_progress or hovered_target == null:
		return
	if selected_target != null and not is_instance_valid(selected_target):
		selected_target = null
	if selected_target == null:
		selected_target = hovered_target
		suppressed_hover_outline = null
	elif selected_target != hovered_target:
		_start_swap(selected_target, hovered_target)
		selected_target = null
	_refresh_outlines()

func _start_swap(first: Node3D, second: Node3D) -> void:
	swap_in_progress = true
	var first_start := first.global_position
	var second_start := second.global_position
	var tween := create_tween()
	var update_motion := Callable(self, "_update_swap_motion").bind(first, second, first_start, second_start)
	tween.tween_method(update_motion, 0.0, 1.0, maxf(swap_duration, 0.01))
	tween.finished.connect(_complete_swap.bind(first, second, first_start, second_start))

func _update_swap_motion(progress: float, first: Node3D, second: Node3D, first_start: Vector3, second_start: Vector3) -> void:
	if not is_instance_valid(first) or not is_instance_valid(second):
		return
	var shake_envelope := sin(progress * PI)
	var shake_phase := progress * TAU * 8.0
	var shake_offset := Vector3(
		sin(shake_phase),
		cos(shake_phase * 0.83),
		sin(shake_phase * 1.17)
	) * swap_shake_strength * shake_envelope
	first.global_position = first_start + shake_offset
	second.global_position = second_start - shake_offset

func _complete_swap(first: Node3D, second: Node3D, first_start: Vector3, second_start: Vector3) -> void:
	if is_instance_valid(first) and is_instance_valid(second):
		var first_scale := first.scale
		var second_scale := second.scale
		first.global_position = second_start
		second.global_position = first_start
		_spawn_swap_puff(first_start)
		_spawn_swap_puff(second_start)

		first.scale = first_scale * 0.12
		second.scale = second_scale * 0.12
		var pop_tween := create_tween().set_parallel(true)
		pop_tween.tween_property(first, "scale", first_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(second, "scale", second_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	swap_in_progress = false
	_refresh_outlines()

func _spawn_swap_puff(effect_position: Vector3) -> void:
	var puff := CPUParticles3D.new()
	puff.amount = 20
	puff.lifetime = 0.2
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.emission_shape = 1
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
	aim_ray.force_raycast_update()
	var next_target: Node3D
	if aim_ray.is_colliding():
		var collider := aim_ray.get_collider()
		if collider is Node3D and collider.is_in_group("swapAble"):
			next_target = collider
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