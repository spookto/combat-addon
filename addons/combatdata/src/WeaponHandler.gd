@tool
@icon("res://addons/combatdata/icons/weapon_handler_icon.svg")
class_name WeaponHandler
extends Node3D

signal weapon_changed
signal active_weapon_changed

signal move_started(move: WeaponMove)
signal move_stopped
signal frame_processed

signal delay_started
signal delay_ended

signal cancel_flag_set(flag: Cancel)

signal damage_inflicted(damage: WeaponDamage)

signal hit_area_added(hit_area: WeaponHitArea)

enum Cancel {
	NONE = 0,
	# Attack Flags
	LIGHT = 1 << 0,
	HEAVY = 1 << 1,
	ANY_ATTACK = 1 << 0 | 1 << 1,
	# Action Flags
	JUMP = 1 << 2,
	DASH = 1 << 3,
	AIR_JUMP = 1 << 4,
	# End Flags
	END_LIGHT = 1 << 5 | 1 << 0,
	END_HEAVY = 1 << 6 | 1 << 1,
	END = 1 << 5 | 1 << 6,
}

## Value that sets the 'frame' to 'target_frame' - 1
const FRAME_PROCESS_ONCE: int = -100
const _MAX_COLLISIONS: int = 8
const DebugView: GDScript = preload("uid://bssyxgy0618c3")

@export var source_skeleton: Skeleton3D
@export var animation_tree: AnimationTree
@export_range(0.0, 2.0, 0.01, "or_greater") var speed_scale: float = 1.0
@export_flags_3d_physics var collision_mask: int = 0xFFFF_FFFF
@export var inherit_velocity_on_start: bool = true

@export var information: WeaponInformation:
	set(value):
		if is_same(information, value):
			return
		information = value
		if information:
			load_weapon_information(information)

		ignore_current_move = true
		weapon_changed.emit()
		if !_current_move:
			active_information = information
@export var can_attack: bool = true

var overrides: WeaponHandlerOverrides = null

var state := WeaponHandlerState.new()
var skeleton: Skeleton3D = null
var active_information: WeaponInformation:
	set(value):
		if active_information == value:
			return
		active_information = value
		active_weapon_changed.emit()

var ignore_current_move: bool = false
var hit_areas: Array[WeaponHitArea] = []

var real_frame: int = -1:
	set(value):
		if real_frame == value:
			return
		real_frame = value
		if real_frame <= 0:
			# Reset frame to start if animation loops
			frame = mini(frame, -1)
			if real_frame < 0:
				paused = true

var frame: int = -1:
	set(value):
		frame = value
		if frame >= 0 and is_instance_valid(animation_tree):
			animation_tree.set(
				&"parameters/Attack/frame",
				frame
			)

var paused: bool = false

var hit_landed: bool = false

var hit_excludes: Array[RID] = []:
	set(value):
		hit_excludes = value
		#if hit_excludes.is_empty():
			#if is_instance_valid(character):
				#hit_excludes = [character.get_rid()]

var delay: float = 0.0:
	set(value):
		value = maxf(value, 0.0)
		var old_delay: float = delay
		delay = value
		if not is_zero_approx(old_delay):
			return
		if is_zero_approx(delay):
			delay_ended.emit()
		else:
			delay_started.emit()

var velocity := Vector3.ZERO
var root_motion_velocity := Vector3.ZERO

var _current_move: WeaponMove
var _current_move_script_instance: Object
var _attack_speed_accumulate: float = 0.0
var _cancel_flags: int = 0
var _current_hit_effect: PackedScene = null
var _pose_modifier: PoseModifier = null
var _seeked_frames: bool = false
# Use to prevent mesh changes when weapon switching mid-combo
var _hold_current_weapon: bool = false
var _animation_library_remaps: Dictionary[String, String] = {}


static func try_get_handler(node: Node) -> WeaponHandler:
	if not is_instance_valid(node):
		return null
	if not node.has_meta(&"_weapon_handler"):
		if Engine.is_editor_hint():
			for child: Node in node.get_children():
				if child is WeaponHandler:
					return child
			return node.find_child("WeaponHandler")
		return null
	return node.get_meta(&"_weapon_handler") as WeaponHandler


static func node_has_handler(node: Node) -> bool:
	return is_instance_valid(try_get_handler(node))


func _enter_tree() -> void:
	add_child(DebugView.new(self))
	if Engine.is_editor_hint():
		return
	owner.set_meta(&"_weapon_handler", self)


func _exit_tree() -> void:
	if is_instance_valid(_current_move_script_instance):
		_current_move_script_instance.free()


func _ready() -> void:
	assert(is_instance_valid(source_skeleton))
	assert(is_instance_valid(animation_tree))

	var tree_root: AnimationNode = animation_tree.tree_root
	if tree_root is AnimationNodeBlendTree:
		if not tree_root.has_node(&"Attack"):
			tree_root.add_node(&"Attack", WeaponHandlerAnimationNode.new())

	skeleton = Skeleton3D.new()
	for i: int in range(source_skeleton.get_bone_count()):
		skeleton.add_bone(source_skeleton.get_bone_name(i))
		skeleton.set_bone_parent(i, source_skeleton.get_bone_parent(i))
		skeleton.set_bone_rest(i, source_skeleton.get_bone_rest(i))
	skeleton.reset_bone_poses()

	skeleton.name = &"WeaponHandlerSkeleton"
	source_skeleton.get_parent().add_child(skeleton)
	skeleton.transform = source_skeleton.transform

	_pose_modifier = PoseModifier.new(self)

	if Engine.is_editor_hint():
		return

	if information:
		load_weapon_information(information)

	assert(
		is_instance_valid(skeleton),
		"%s: WeaponHandler cannot work without a Skeleton3D node!" % owner.scene_file_path
	)


func _physics_process(delta: float) -> void:
	delay -= delta

	if paused:
		return

	# Calculate attack speed
	var speed: float = Engine.time_scale * speed_scale

	# Early return if speed is zero, same as being paused
	if is_zero_approx(speed):
		return

	var speed_delta: float = speed - 1.0

	if real_frame < 0 || !_current_move:
		return

	if frame > real_frame:
		frame = real_frame - 1

	while frame < real_frame && real_frame >= 0:
		frame += 1
		process_frame()

	# Do not change frame if we manually seeked it
	if _seeked_frames:
		_seeked_frames = false
		return

	# Calculate frame adjustment based on timescale and attack speed
	var frame_add: int = 0
	for _i: int in range(1):
		frame_add += 1

		if is_zero_approx(speed_delta):
			continue
		_attack_speed_accumulate += speed_delta
		while absf(_attack_speed_accumulate) >= 1.0:
			var accumulate_sign: int = signi(roundi(_attack_speed_accumulate))
			frame_add += accumulate_sign
			_attack_speed_accumulate -= accumulate_sign

	# Apply frame adjustment only once, this eliminates weird behavior at low timescales
	real_frame += frame_add


func set_can_attack(value: bool) -> void:
	can_attack = value


func get_current_move() -> WeaponMove:
	return _current_move


func get_current_animation() -> Animation:
	if not _current_move:
		return null
	return animation_tree.get_animation(_remap_animation(_current_move.animation))


## Skips animation forward and runs all skipped logic.
func skip_frames(amount: int) -> void:
	real_frame += amount


## Moves animation to the selected frame and runs all logic between them
## if [code]skip_logic[/code] is set to true.
func seek_frames(amount: int, skip_logic: bool = false) -> void:
	real_frame = amount
	if skip_logic:
		frame = amount - 1
	_seeked_frames = true


## Runs the current frame's logic and emits [signal WeaponHandler.frame_processed] after completion.
func process_frame() -> void:
	# Ensures that bones are exactly where we want them.
	_pose_modifier.apply_pose()

	_move_process()
	_hit_process()
	frame_processed.emit()


func start_move(move: WeaponMove) -> void:
	if not can_attack:
		return
	if not is_instance_valid(animation_tree):
		return
	# Move isn't valid, probably just for showing something in the movelist
	if move.logic.is_empty():
		stop_move()
		return
	if _current_move:
		_current_move = move
		move_stopped.emit()

	if not _hold_current_weapon:
		if ignore_current_move:
			if !information || information.moves.has(move):
				active_information = information
		else:
			active_information = information
	_hold_current_weapon = false

	ignore_current_move = false
	_current_move = move
	end_delay()
	reset_properties()
	_update_hit_effect()
	real_frame = 0
	_play_move_animation()

	if is_instance_valid(_current_move_script_instance):
		# Defer freeing to ensure current move's logic doesn't stop abruptly
		_current_move_script_instance.free.call_deferred()

	_current_move_script_instance = _current_move.get_move_script().new()

	velocity = Vector3.ZERO
	if inherit_velocity_on_start:
		if owner is CharacterBody3D:
			velocity = owner.velocity
	move_started.emit(_current_move)


func stop_move() -> void:
	if _current_move == null:
		return
	reset_properties()
	_current_move = null
	active_information = information
	move_stopped.emit()
	real_frame = -1


func pause_move() -> void:
	paused = true


func continue_move() -> void:
	paused = false
	real_frame += 1


func reset_properties() -> void:
	clear_cancel_flags()
	hit_landed = false
	paused = false
	hit_areas = []
	hit_excludes = []
	_current_hit_effect = null


func rearm() -> void:
	hit_excludes = []
	if Engine.is_editor_hint():
		set_meta(&"rearmed", frame)
		remove_meta.call_deferred(&"rearmed")


func set_delay(duration: float = 0.35) -> void:
	delay = duration


func end_delay() -> void:
	delay = 0.0


## Creates a new hit area attached to the target bone
func hit_area(
	bone: String, length: float, radius: float, offset: Vector3 = Vector3.ZERO, duration: int = 1
) -> WeaponHitArea:
	var new_area: WeaponHitArea = WeaponHitArea.new(
		skeleton.find_bone(bone), length, radius, offset, duration, frame, _current_move
	)
	# Current move doesn't have damage, so instantly return and RefCounted will throw it away later
	if _current_move.damage.is_empty():
		push_warning(
			"Move '%s' (%s) added a hit area at frame %d when move has no damage!" % [
				_current_move.name,
				_current_move.resource_path,
				frame,
			]
		)
		return new_area

	for area: WeaponHitArea in hit_areas:
		if area.is_equal_to(new_area):
			new_area.unreference()
			return area
	hit_areas.append(new_area)
	hit_area_added.emit.bind(new_area).call_deferred()

	return new_area


## Sends attack input to weapon handler
func attack_input(input: WeaponMove.MoveInput = WeaponMove.MoveInput.NONE) -> bool:
	if Engine.is_editor_hint() and get_meta(&"lock_move", false):
		return false
	var next_move: WeaponMove = _get_next_move(input)
	if !next_move:
		return false

	# Don't change weapon visuals if attack is NONE
	_hold_current_weapon = input == WeaponMove.MoveInput.NONE

	start_move(next_move)
	return true


func set_cancel_flag(flag: Cancel) -> WeaponHandler:
	_cancel_flags |= flag
	if Engine.is_editor_hint():
		return self

	cancel_flag_set.emit(flag)
	return self


func set_cancel_flags(flags: Array[Cancel]) -> WeaponHandler:
	for flag: Cancel in flags:
		set_cancel_flag(flag)
	return self


func unset_cancel_flag(flag: Cancel) -> WeaponHandler:
	_cancel_flags &= ~flag
	return self


func is_cancel_flag(flag: Cancel) -> bool:
	return (_cancel_flags & flag) == flag


func clear_cancel_flags() -> void:
	_cancel_flags = Cancel.NONE


func get_hit_effect() -> PackedScene:
	return _current_hit_effect


func load_weapon_information(weapon_information: WeaponInformation) -> void:
	_add_animation_library(weapon_information)


## Uses the hitbox skeleton for more deterministic locations.
func spawn_at_bone(path: Variant, bone: StringName, offset: Vector3 = Vector3.ZERO) -> Node:
	var bone_idx: int = skeleton.find_bone(bone)
	assert(bone_idx > -1, "WeaponHandler.gd: Bone of name '%s' does not exist" % bone)

	var bone_transform := skeleton.global_transform * skeleton.get_bone_global_pose(
		bone_idx
	).orthonormalized().translated_local(offset)

	#return Node.new()
	#TODO Implement this
	return null


func _add_animation_library(weapon_information: WeaponInformation) -> void:
	if not is_instance_valid(animation_tree) or not weapon_information:
		return
	var library_name: StringName = weapon_information.get_animation_library_name()
	if animation_tree.has_animation_library(library_name):
		return
	for lib_key: StringName in animation_tree.get_animation_library_list():
		var lib: AnimationLibrary = animation_tree.get_animation_library(lib_key)
		if is_same(lib, weapon_information.animation_library):
			_animation_library_remaps[library_name] = lib_key
			return
	animation_tree.add_animation_library(library_name, weapon_information.animation_library)


func _get_next_move(input: WeaponMove.MoveInput) -> WeaponMove:
	if !information && !_current_move:
		return null

	var moves: Array[WeaponMove] = []
	if information:
		moves = information.moves

	var next_move: WeaponMove = null

	# HACK Preserve old logic
	if (
		is_cancel_flag(Cancel.END)
		and (is_cancel_flag(Cancel.LIGHT) == is_cancel_flag(Cancel.HEAVY))
	):
		set_cancel_flag(Cancel.ANY_ATTACK)

	# HACK Ensure multi-move attacks execute as expected
	if input == WeaponMove.MoveInput.NONE:
		ignore_current_move = false

	# Get next move from current move's movelist
	if _current_move && not ignore_current_move:
		match input:
			WeaponMove.MoveInput.NONE:
				if not is_cancel_flag(Cancel.END):
					moves = _current_move.next_moves

			WeaponMove.MoveInput.LIGHT:
				if not is_cancel_flag(Cancel.LIGHT):
					return null
				if not is_cancel_flag(Cancel.END_LIGHT):
					moves = _current_move.next_moves

			WeaponMove.MoveInput.HEAVY:
				if not is_cancel_flag(Cancel.HEAVY):
					return null
				if not is_cancel_flag(Cancel.END_HEAVY):
					moves = _current_move.next_moves

	if moves.is_empty():
		return null

	# Moves are iterated from top to bottom, with the lowest move in the array taking priority.
	for move: WeaponMove in moves:
		# Skip moves with incompatible input
		if move.input != input:
			continue

		# Skip impossible moves
		if not _check_move_conditions(move):
			continue

		# Skip disabled moves
		if overrides and overrides.is_move_disabled(move):
			continue

		next_move = move

	return next_move


func _check_move_conditions(move: WeaponMove) -> bool:
	if move.conditions == 0:
		return true
	var air_ok: bool = (
		move.conditions & (1 << WeaponMove.Condition.GROUND - 1)
		&& move.conditions & (1 << WeaponMove.Condition.AIR - 1)
	)

	var can_be_done: bool = true

	for i: int in range(WeaponMove.Condition.size()):
		if move.conditions & (1 << i):
			match i + 1:
				# Grounded
				WeaponMove.Condition.GROUND:
					if !air_ok && !state.grounded:
						can_be_done = false
				# Air
				WeaponMove.Condition.AIR:
					if !air_ok && state.grounded:
						can_be_done = false
				# Delay
				WeaponMove.Condition.DELAY:
					if is_zero_approx(delay):
						can_be_done = false
				# Dash
				WeaponMove.Condition.DASH:
					if not state.dashing:
						can_be_done = false
				# JUMP
				WeaponMove.Condition.JUMP:
					if not state.jumped:
						can_be_done = false
				# Move Stick Forward
				WeaponMove.Condition.MOVE_STICK_FORWARD:
					if true:
						can_be_done = false

	return can_be_done


#region Processing
## Process frame logic and hitbox durations
func _move_process() -> void:
	if !_current_move:
		return

	_current_move_script_instance.call(&"frame_process", frame, self, information, _current_move)


## Process collision and damage logic
func _hit_process() -> void:
	hit_landed = false

	if _current_move == null || _current_move.damage.is_empty():
		return

	if Engine.is_editor_hint():
		for area: WeaponHitArea in hit_areas:
			if area.is_disabled(frame):
				continue
			area.get_area_transform(skeleton)
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.collide_with_areas = true
	shape_query.collide_with_bodies = true
	shape_query.collision_mask = collision_mask

	# Check collision for available hit areas.
	for area: WeaponHitArea in hit_areas:
		if area.is_disabled(frame):
			continue

		shape_query.shape = area.get_shape()
		shape_query.exclude = hit_excludes
		shape_query.transform = area.get_area_transform(skeleton)

		var result: Array[Dictionary] = space_state.intersect_shape(
			shape_query,
			mini(_MAX_COLLISIONS, area.hit_limit)
			)

		if result.is_empty():
			continue

		area.hits += result.size()
		hit_landed = true

		for dict: Dictionary in result:
			var collider: Node = dict["collider"]
			if collider is CollisionObject3D:
				_try_damage(area, collider)


func _try_damage(area: WeaponHitArea, target: CollisionObject3D) -> void:
	var rid: RID = target.get_rid()
	if hit_excludes.has(rid):
		return

	#HACK: Prevents double damage against proxy hitareas
	if target.owner is CollisionObject3D:
		if hit_excludes.has(target.owner.get_rid()):
			return

	var damage_return: WeaponDamage = area.apply_damage(self, target)
	if damage_return:
		damage_inflicted.emit(damage_return)

		if damage_return.has_meta(&"alt_target_rid"):
			hit_excludes.append(damage_return.get_meta(&"alt_target_rid"))

	# HACK: Only exclude single target, TODO: Rework this to have excludes per hitarea instead.
	if is_instance_valid(area.only_damage_target):
		if damage_return:
			hit_excludes.append(rid)
	else:
		hit_excludes.append(rid)
#endregion


func _update_hit_effect() -> void:
	if _current_move:
		_current_hit_effect = _current_move.hit_effect
	if !_current_hit_effect && active_information:
		_current_hit_effect = active_information.default_hit_effect


func _play_move_animation() -> void:
	if !_current_move || not is_instance_valid(animation_tree):
		return
	animation_tree.set(
		&"parameters/Attack/animation",
		type_convert(_current_move.animation, TYPE_STRING)
	)


func _remap_animation(anim_name: String) -> String:
	for remap_from: String in _animation_library_remaps:
		if not anim_name.begins_with(remap_from):
			continue
		anim_name = _animation_library_remaps[remap_from] + anim_name.trim_prefix(remap_from)
	return anim_name


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		remove_meta(&"rearmed")


class PoseModifier extends RefCounted:
	var _handler: WeaponHandler
	var _animation: Animation = null
	var _skeleton: Skeleton3D
	var _track_prefix: String = "Skeleton3D:"
	var _bones_count: int = 0
	var _anim_time: float = 0.0

	var _pos_track: int = -1
	var _rot_track: int = -1

	var _root_bone: int = -1
	var _root_position: Vector3
	var _reset_root_motion: bool = true

	func _init(weapon_handler: WeaponHandler) -> void:
		_handler = weapon_handler
		_handler.move_started.connect(_on_move_started.unbind(1))

		_skeleton = _handler.skeleton

		var root_motion_track: String = _handler.animation_tree.root_motion_track

		if not root_motion_track.is_empty():
			_root_bone = _skeleton.find_bone(root_motion_track.get_slice(":", 1))

		var anim_tree: AnimationTree = _handler.animation_tree
		_track_prefix = (
			"%s:" % anim_tree.get_node(anim_tree.root_node).get_path_to(_handler.source_skeleton)
		)
		_bones_count = _skeleton.get_bone_count()

	func apply_pose() -> void:
		if not _animation:
			return
		_anim_time = float(_handler.frame) / Engine.physics_ticks_per_second

		for i: int in range(0, _bones_count):
			var pose: Transform3D = _calculate_bone_pose(i)
			if i == _root_bone:
				if _reset_root_motion:
					_root_position = pose.origin
					_reset_root_motion = false
				_handler.root_motion_velocity = pose.origin - _root_position
				_root_position = pose.origin
				continue
			_skeleton.set_bone_pose(i, pose)

	func _calculate_bone_pose(bone_index: int) -> Transform3D:
		var out_transform: Transform3D
		var track: String = _bone_to_track_name(bone_index)

		_pos_track = _animation.find_track(track, Animation.TYPE_POSITION_3D)
		if _pos_track != -1:
			out_transform.origin = _animation.position_track_interpolate(_pos_track, _anim_time)
		else:
			out_transform.origin = _skeleton.get_bone_pose(bone_index).origin

		_rot_track = _animation.find_track(track, Animation.TYPE_ROTATION_3D)
		if _rot_track != -1:
			out_transform.basis = Basis(
				_animation.rotation_track_interpolate(_rot_track, _anim_time)
			)
		else:
			out_transform.basis = _skeleton.get_bone_pose(bone_index).basis

		return out_transform

	func _bone_to_track_name(bone_index: int) -> String:
		return _track_prefix + _skeleton.get_bone_name(bone_index)

	func _on_move_started() -> void:
		_animation = _handler.get_current_animation()
		_reset_root_motion = true
