extends Node

const _COLOR_X:= Color(0.96, 0.2, 0.32)
const _COLOR_Y:= Color(0.53, 0.84, 0.01)
const _COLOR_Z:= Color(0.16, 0.55, 0.96)

var handler: WeaponHandler = null

var _cache: Array[MeshInstance3D] = []
var _axis_canvas: CanvasLayer
var _axis_control: Control = Control.new()
var _axis_transforms: Array[Transform3D] = []

func _init(_handler: WeaponHandler) -> void:
	handler = _handler
	_cache = []
	name = "WeaponHandlerDebugView"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_meta(&"_debug_hidden", true)


func _ready() -> void:
	if !Engine.is_editor_hint():
		if !get_tree().debug_collisions_hint:
			set_process(false)
			queue_free()
			return
	_axis_canvas = CanvasLayer.new()
	_axis_canvas.layer = 200
	add_child(_axis_canvas)
	_axis_canvas.add_child(_axis_control)
	_axis_control.draw.connect(_draw_axis)

	process_priority = handler.process_priority + 10


func _process(_delta: float) -> void:
	if not is_instance_valid(handler.skeleton):
		return

	_axis_transforms.clear()
	propagate_call(&"hide")

	var index: int = 0

	for area: WeaponHitArea in handler.hit_areas:
		var color: Color = Color.RED

		if area.get_move().damage.is_empty():
			continue

		if area.is_probe():
			color = Color.AQUA

		if area.is_disabled(handler.frame):
			color = Color.WEB_GRAY

		var color_t: Color = color * 0.4

		var mesh: ArrayMesh = area.get_shape().get_debug_mesh()

		var material: StandardMaterial3D = _create_material(color)
		var material_fill: StandardMaterial3D = _create_material(color_t)

		var instance: MeshInstance3D = get_mesh(index)
		instance.transform = area.get_area_transform(handler.skeleton)
		instance.mesh = mesh
		instance.set_surface_override_material(0, material)
		instance.set_surface_override_material(1, material_fill)
		instance.visible = true

		index += 1

func get_mesh(index: int) -> MeshInstance3D:
	if index >= _cache.size():
		return create_new_mesh()
	return _cache[index]

func create_new_mesh() -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	add_child(m)
	_cache.append(m)
	return m

func _create_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = int(color.a < 0.5) - 2
	material.albedo_color = color
	material.disable_fog = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	return material


func _draw_axis() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return

	for axis_transform: Transform3D in _axis_transforms:
		var origin: Vector2 = camera.unproject_position(axis_transform.origin)
		var x_end: Vector2 = camera.unproject_position(
			axis_transform.origin + axis_transform.basis.x
			)
		var y_end: Vector2 = camera.unproject_position(
			axis_transform.origin + axis_transform.basis.y
			)
		var z_end: Vector2 = camera.unproject_position(
			axis_transform.origin + axis_transform.basis.z
			)

		_axis_control.draw_line(
			origin,
			x_end,
			_COLOR_X
		)
		_axis_control.draw_circle(x_end, 4.0, _COLOR_X)

		_axis_control.draw_line(
			origin,
			y_end,
			_COLOR_Y
		)
		_axis_control.draw_circle(y_end, 4.0, _COLOR_Y)

		_axis_control.draw_line(
			origin,
			z_end,
			_COLOR_Z
		)
		_axis_control.draw_circle(z_end, 4.0, _COLOR_Z)
