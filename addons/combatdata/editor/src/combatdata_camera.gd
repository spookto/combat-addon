@tool
extends Camera3D

const MOVE_MULTIPLIER: float = 6.0
const _RESET_ROTATION: StringName = &"reset_rotation"
const _M_FORWARD: StringName = &"mforward"
const _M_BACK: StringName = &"mback"
const _M_LEFT: StringName = &"mleft"
const _M_RIGHT: StringName = &"mright"

@export var viewport_container: SubViewportContainer = null

var controlling: bool = false

func _enter_tree():
	_check_input(_M_FORWARD, KEY_W)
	_check_input(_M_BACK, KEY_S)
	_check_input(_M_LEFT, KEY_A)
	_check_input(_M_RIGHT, KEY_D)


func _ready() -> void:
	if is_instance_valid(viewport_container):
		viewport_container.gui_input.connect(_on_sub_viewport_container_gui_input)


func _process(delta: float) -> void:
	if !controlling:
		return

	var input: Vector2 = Input.get_vector(_M_LEFT, _M_RIGHT, _M_BACK, _M_FORWARD) * MOVE_MULTIPLIER
	if input.length_squared() <= 0.1:
		return

	translate(Vector3.FORWARD * input.y * delta)
	translate(Vector3.RIGHT * input.x * delta)
	owner.call("refresh_animation")


func _check_input(input_name: StringName, input_keycode: int) -> void:
	if not InputMap.has_action(input_name):
		InputMap.add_action(input_name)
	var event = InputEventKey.new()
	event.physical_keycode = input_keycode
	InputMap.action_add_event(input_name, event)


func _on_sub_viewport_container_gui_input(event: InputEvent):
	if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_RIGHT:
		controlling = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if controlling else Input.MOUSE_MODE_VISIBLE
		viewport_container.accept_event()
		if controlling:
			viewport_container.grab_focus()

	if !controlling:
		return

	viewport_container.accept_event()

	if event is InputEventMouseMotion:
		global_rotate(Vector3.UP, -event.relative.x * 0.01)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * 0.01)
		owner.call("refresh_animation")


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	properties.append({
		"name": _RESET_ROTATION,
		"type": TYPE_BOOL,
	})

	return properties

func _get(property: StringName):
	if property == _RESET_ROTATION:
		return false

func _set(property: StringName, value: Variant) -> bool:
	if property == _RESET_ROTATION:
		if is_inside_tree():
			look_at(Vector3.ZERO)
		return true
	return false
