@tool
class_name WeaponMove
extends Resource

enum Condition {
	NONE = 0,
	GROUND = 1,
	AIR = 2,
	DELAY = 3,
	DASH = 4,
	JUMP = 5,
	MOVE_STICK_FORWARD = 6,
}

enum VisualFlag {
	PROPAGATE_ATTRIBUTES_UP = 1 << 0,
	EXCLUDE_IF_ROOT = 1 << 1,
}

enum MoveInput {
	NONE = -1,
	LIGHT = 0,
	HEAVY = 1,
	# Used by enemies and bosses
	EXTRA_1 = 2,
	EXTRA_2 = 3,
	EXTRA_3 = 4,
	EXTRA_4 = 5,
}

const SCRIPT_TEMPLATE: String = "@tool
extends Object

@warning_ignore(\"unused_parameter\")
func frame_process(frame: int, handler: WeaponHandler, weapon: WeaponInformation, move: WeaponMove) -> void:
"

@export var name: StringName = "New Move"
@export var input: MoveInput = MoveInput.LIGHT
@export var next_moves: Array[WeaponMove] = []
@export var animation: StringName = ""
@export_multiline var logic: String = "if frame>30:# Replace with animation's end
	handler.stop_move()
	return

# Run logic on specific frames using match statements
match frame:
	0:
		# Initialize gravity, velocity, drag, variables, etc here
		character.set_attack_drag(8.0)
		character.set_attack_gravity(16.0)
		character.set_velocity_local(Vector3(0,0,-10))
":
	set(value):
		logic = value
		if OS.is_debug_build():
			# Allow hot-reloading to work
			_cached_code = ""
			_cached_script = null
@export_flags(".") var conditions: int = Condition.GROUND | Condition.AIR:
	set(value):
		conditions = value
		notify_property_list_changed()
@export var damage: Array[WeaponDamage] = []
@export var spawnables: Array[PackedScene] = []
@export var tracks: Array[WeaponTrack] = []
@export_group("Hit Visuals")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var hit_effect_enabled: bool = true
@export var hit_effect: PackedScene = null
@export_group("Visuals")
@export var hidden: bool = false
## Completely excluded from moveset, not even input glyphs are drawn.
@export var exclude_from_movelist: bool = false
@export var visual_input: MoveInput = MoveInput.NONE
@export var visual_hold: bool = false
@export var visual_flags: int = 0
@export var visual_exclude_if_child: bool = false
@export_group("Behaviour", "behaviour_")
@export var behaviour_no_mesh_visuals: bool = false

# ONLY VISUAL, does NOT affect actual behavior
var propagate_attributes_up: bool:
	get:
		return visual_flags & VisualFlag.PROPAGATE_ATTRIBUTES_UP
	set(value):
		if value:
			visual_flags |= VisualFlag.PROPAGATE_ATTRIBUTES_UP
		else:
			visual_flags &= ~VisualFlag.PROPAGATE_ATTRIBUTES_UP
var _cached_code: String = "":
	get:
		if Engine.is_editor_hint():
			return ""
		return _cached_code
var _cached_script: GDScript = null:
	get:
		if Engine.is_editor_hint():
			return null
		return _cached_script


func _validate_property(property: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return

	if property.name == &"conditions":
		var hint_keys: PackedStringArray = []
		for key: String in Condition.keys():
			var bit: int = Condition.get(key) - 1
			if bit < 0:
				continue
			hint_keys.append("%s:%d" % [key.capitalize(), 1 << bit])
		property.hint_string = ",".join(hint_keys)


func is_condition(condition: int) -> bool:
	return conditions & (1 << (condition - 1))


func get_condition_text() -> String:
	var condition: String = ""
	for i in range(8):
		if conditions & (1 << i):
			match i + 1:
				WeaponMove.Condition.GROUND:
					condition = "Ground Only"
				WeaponMove.Condition.AIR:
					condition = "Air Only" if condition.is_empty() else "Air OK"
				#WeaponMove.Condition.DASH:
				#condition += " Dash"
	condition += " " + get_delay_text()
	return condition


func get_delay_text() -> String:
	var d: bool = conditions & (1 << (WeaponMove.Condition.DELAY - 1))

	return "Delay" if d else ""


func get_visible_next_moves() -> Array[WeaponMove]:
	return next_moves.filter(func(move: WeaponMove) -> bool:
		if move.exclude_from_movelist:
			return false
		elif move.visual_exclude_if_child:
			return false
		return true
	)


func get_draw_input() -> MoveInput:
	if visual_input != MoveInput.NONE:
		return visual_input
	return input


func can_draw() -> bool:
	if hidden:
		return false
	return get_draw_input() != MoveInput.NONE


func get_move_script() -> GDScript:
	if _cached_script != null:
		return _cached_script
	var new_script: GDScript = GDScript.new()
	new_script.source_code = _get_move_code()
	new_script.reload()
	_cached_script = new_script
	return new_script


func get_attributes() -> int:
	var attributes: int = 0
	for dinfo: WeaponDamage in damage:
		attributes |= dinfo.attributes
	return attributes


func _get_move_code(include_tracks: bool = true) -> String:
	if !_cached_code.is_empty():
		return _cached_code
	var out: String = SCRIPT_TEMPLATE

	var logic_text: String = logic
	if include_tracks:
		for track: WeaponTrack in tracks:
			logic_text = track.compile() + "\n" + logic_text

	out += logic_text.indent("\t")
	_cached_code = out
	return out
