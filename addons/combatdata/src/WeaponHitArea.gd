@tool
class_name WeaponHitArea
extends RefCounted

var transform: Transform3D
var hit_limit: int = 1000

var hits: int = 0
var only_damage_target: Node = null

var cached_hash: int = 0

var _bone_index: int = -1
var _length: float = 1.0
var _radius: float = 0.5
# Rotates X and Z axis locally, angles are expected to be in radians.
var _rotation: Vector2 = Vector2.ZERO
var _offset: Vector3 = Vector3.ZERO
var _duration: int = 1
var _start_frame: int = 0
var _damage_index: int = 0
var _move: WeaponMove
var _shape: CapsuleShape3D
var _use_visual_basis: bool = false
var _visual_basis: Basis = Basis.IDENTITY

func _init(
	bone_index: int, length: float, radius: float,
	offset: Vector3, duration: int, start_frame: int, move: WeaponMove
	) -> void:
	_bone_index = bone_index
	_length = length
	_radius = radius
	_offset = offset
	_duration = duration
	_start_frame = start_frame
	_move = move

	_shape = CapsuleShape3D.new()
	_shape.height = _length
	_shape.radius = _radius

	_update_hash()


func is_disabled(frame: int) -> bool:
	if hits >= hit_limit:
		return true
	return (frame < _start_frame || frame > _start_frame + _duration)


func get_duration() -> int:
	return _duration


func set_duration(amount: int) -> WeaponHitArea:
	_duration = amount
	_update_hash()
	return self


func set_rotation(rotation: Vector2) -> WeaponHitArea:
	_rotation = rotation
	_update_hash()
	return self


func set_hit_limit(amount: int) -> WeaponHitArea:
	hit_limit = amount
	return self


func set_damage_index(index: int) -> WeaponHitArea:
	_damage_index = index
	_update_hash()
	return self


func vfx_basis(basis: Basis) -> WeaponHitArea:
	_use_visual_basis = true
	_visual_basis = basis.orthonormalized()
	return self


func vfx_basis_axis(z_axis: Vector3, y_axis: Vector3) -> WeaponHitArea:
	_use_visual_basis = true
	_visual_basis = Basis(y_axis.cross(z_axis), y_axis, z_axis).orthonormalized()
	return self


func vfx_basis_character_y(basis: Basis, direction: Vector3) -> WeaponHitArea:
	direction = direction.normalized()
	var forward: Vector3 = basis.z
	var y_axis: Vector3 = basis * direction
	if y_axis.is_equal_approx(forward):
		forward = basis.x
	forward = y_axis.cross(forward).normalized()

	return vfx_basis_axis(forward, y_axis)


func vfx_basis_direction(direction: Vector3) -> WeaponHitArea:
	_use_visual_basis = true
	direction = direction.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 1.0 else Vector3.FORWARD
	_visual_basis = Basis.looking_at(direction, up)
	return self


func only_damage(node: Node) -> WeaponHitArea:
	only_damage_target = node
	return self


func get_damage() -> WeaponDamage:
	return _move.damage[_damage_index]


func get_move() -> WeaponMove:
	return _move


func apply_damage(handler: WeaponHandler, target: Node) -> WeaponDamage:
	if is_probe():
		return null
	if is_instance_valid(only_damage_target) and target != only_damage_target:
		return null
	var damage: WeaponDamage = get_damage().from(handler)
	if _use_visual_basis:
		damage.set_meta(&"visual_basis", _visual_basis)
	damage.set_meta(&"move", _move)
	#if not Damageable.try_damage(target, damage):
		#return null
	return damage


func is_probe() -> bool:
	return get_damage().is_probe()


func get_shape() -> CapsuleShape3D:
	return _shape


func get_area_transform_local(skeleton: Skeleton3D) -> Transform3D:
	var out: Transform3D = Transform3D.IDENTITY
	if _bone_index >= 0:
		out = skeleton.get_bone_global_pose(_bone_index)
	out.origin = out.origin + (out.basis * _offset)
	out.basis = out.basis.rotated(out.basis.x, _rotation.x)
	out.basis = out.basis.rotated(out.basis.z, _rotation.y)
	return out.orthonormalized()

## Calculates and returns global area transform based on target bone and parameters.
func get_area_transform(skeleton: Skeleton3D) -> Transform3D:
	transform = skeleton.global_transform * get_area_transform_local(skeleton)
	return transform


func is_equal_to(other: WeaponHitArea) -> bool:
	return self.cached_hash == other.cached_hash


func _update_hash() -> void:
	cached_hash = [
		_bone_index,
		_length,
		_radius,
		_rotation,
		_offset,
		_duration,
		_start_frame,
		#_damage_index,
	].hash()
