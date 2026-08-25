extends CharacterBody3D

const FLAT := Vector3(1.0, 0.0, 1.0)

@export_custom(0, "suffix:m/s") var speed: float = 8.0
@export_custom(0, "suffix:s") var attack_buffer: float = 0.1
@export var root_motion: bool = true
@export var jump_cancels_all: bool = false

var camera: Camera3D

var _jump_buffer: float = -1.0
var _light_buffer: float = -1.0
var _heavy_buffer: float = -1.0
var _time_since_jump: float = -1.0

@onready var animation_tree: AnimationTree = %AnimationTree
@onready var weapon_handler: WeaponHandler = %WeaponHandler

func _ready() -> void:
	camera = get_viewport().get_camera_3d()
	assert(is_instance_valid(camera))
	weapon_handler.move_started.connect(func(_m) -> void:
		animation_tree.set(&"parameters/Transition/transition_request", "attack")
	)
	weapon_handler.move_stopped.connect(func() -> void:
		animation_tree.set(&"parameters/Transition/transition_request", "default")
	)


func _physics_process(delta: float) -> void:
	_jump_buffer -= delta
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = attack_buffer
	if Input.is_action_just_pressed(&"attack_light"):
		_light_buffer = attack_buffer
	if Input.is_action_just_pressed(&"attack_heavy"):
		_heavy_buffer = attack_buffer

	weapon_handler.state.grounded = is_on_floor()
	weapon_handler.state.jumped = _time_since_jump > 0.0
	_time_since_jump -= delta

	if _heavy_buffer > 0.0:
		_heavy_buffer -= delta
		if weapon_handler.attack_input(WeaponMove.MoveInput.HEAVY):
			_heavy_buffer = -1.0

	if _light_buffer > 0.0:
		_light_buffer -= delta
		if weapon_handler.attack_input(WeaponMove.MoveInput.LIGHT):
			_light_buffer = -1.0

	if weapon_handler.get_current_move():
		if root_motion:
			move_and_collide(
				weapon_handler.root_motion_velocity * weapon_handler.skeleton.global_basis.inverse() * weapon_handler.speed_scale
			)
		velocity = weapon_handler.velocity * weapon_handler.speed_scale
		var can_jump: bool = jump_cancels_all or weapon_handler.is_cancel_flag(WeaponHandler.Cancel.JUMP)
		if can_jump and _jump():
			weapon_handler.stop_move()
		move_and_slide()
	else:
		_movement_process(delta)

	animation_tree.set(&"parameters/StateMachine/conditions/grounded", is_on_floor())
	animation_tree.set(&"parameters/StateMachine/conditions/in_air", not is_on_floor())


func _movement_process(delta: float) -> void:
	var move := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")

	var cam_x: Vector3 = (camera.global_basis.x * FLAT).normalized()
	var cam_z: Vector3 = (camera.global_basis.z * FLAT).normalized()
	var cam_dir: Vector3 = (cam_x * move.x) + (cam_z * move.y)

	velocity += get_gravity() * delta
	velocity = Vector3(cam_dir.x * speed, velocity.y, cam_dir.z * speed)

	_jump()

	move_and_slide()

	var standing: bool = move.is_zero_approx()

	animation_tree.set(&"parameters/StateMachine/conditions/idle", standing)
	animation_tree.set(&"parameters/StateMachine/conditions/run", not standing)

	if not standing:
		rotation.y = lerp_angle(rotation.y, atan2(-cam_dir.x, -cam_dir.z), 12.0 * delta)


func _jump() -> bool:
	if _jump_buffer > 0.0 and is_on_floor():
		velocity.y = 5.0
		_time_since_jump = 0.15
		_jump_buffer = -1.0
		return true
	return false
