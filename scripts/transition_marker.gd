@tool
extends Area3D

## Editor-only cube; the Area3D remains active and invisible during gameplay.
@export_enum("Переход в локацию", "Флэшбэк") var transition_style: int = 0:
	set(value):
		transition_style = value
		if is_node_ready():
			_update_preview()

var preview: MeshInstance3D
var caption: Label3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	preview = MeshInstance3D.new()
	preview.name = "EditorCube"
	preview.mesh = BoxMesh.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	caption = Label3D.new()
	caption.name = "EditorCaption"
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.font_size = 42
	caption.pixel_size = 0.008
	add_child(caption)
	_update_preview()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_preview()

func _update_preview() -> void:
	if not is_instance_valid(preview):
		return
	var collision: CollisionShape3D
	for child in get_children():
		if child is CollisionShape3D:
			collision = child
			break
	var box_size := Vector3.ONE
	if collision != null and collision.shape is BoxShape3D:
		box_size = collision.shape.size
		preview.transform = collision.transform
	(preview.mesh as BoxMesh).size = box_size
	var color := Color(1.0, 0.83, 0.4, 0.2) if transition_style == 1 else Color(0.25, 0.55, 0.95, 0.2)
	var material := preview.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		preview.material_override = material
	material.albedo_color = color
	caption.text = "Флэшбэк\nБелый экран" if transition_style == 1 else "Переход в локацию\nЗатемнение экрана"
	caption.position = preview.position + Vector3(0, box_size.y * 0.5 + 0.4, 0)
