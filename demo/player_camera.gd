extends Node3D

var _parent3d: Node3D

func _init() -> void:
	top_level = true
	# Disable physics interpolation on camera to ensure smoothness if enabled in ProjectSettings.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _enter_tree() -> void:
	_parent3d = get_parent() as Node3D
	assert(is_instance_valid(_parent3d))


func _process(delta: float) -> void:
	position = position.move_toward(
		_parent3d.get_global_transform_interpolated().origin,
		8.0 * delta
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate(Vector3.UP, -event.screen_relative.x * 0.01)
