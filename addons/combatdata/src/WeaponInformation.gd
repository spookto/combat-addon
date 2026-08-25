@tool
class_name WeaponInformation
extends Resource

enum HolsterType {
	HIDE,
	EQUIP_MESH,
	BONE_ATTACHMENT_MESH,
}

const LIGHT_ICON_PATH: String = "res://addons/combatdata/icons/light_attack.svg"
const LIGHT_HOLD_ICON_PATH: String = "res://addons/combatdata/icons/light_attack_hold.svg"
const HEAVY_ICON_PATH: String = "res://addons/combatdata/icons/heavy_attack.svg"
const HEAVY_HOLD_ICON_PATH: String = "res://addons/combatdata/icons/heavy_attack_hold.svg"
const DASH_ICON_PATH: String = "res://addons/combatdata/icons/dash.svg"
const MOVE_FORWARD_ICON_PATH: String = "res://addons/kenney_input-prompts/common/stick_l_all.svg"
const NEXT_ICON_PATH: String = "res://addons/combatdata/icons/next_attack.svg"
const EMPTY_ICON_PATH: String = "res://addons/combatdata/icons/empty_attack.svg"

const ICONS_DICT: Dictionary = {
	# Inputs
	"light": LIGHT_ICON_PATH,
	"light_hold": LIGHT_HOLD_ICON_PATH,
	"heavy": HEAVY_ICON_PATH,
	"heavy_hold": HEAVY_HOLD_ICON_PATH,
	"dash": DASH_ICON_PATH,
	"move_forward": MOVE_FORWARD_ICON_PATH,
	# Behaviour
	"next": NEXT_ICON_PATH,
	"delay": LIGHT_ICON_PATH,
	# Other
	"empty": EMPTY_ICON_PATH,
	# Attributes
	"atr_launcher": "res://addons/combatdata/icons/atr_launcher.svg",
	"atr_barrage": "res://addons/combatdata/icons/atr_barrage.svg",
	"atr_stun": "res://addons/combatdata/icons/atr_stun.svg",
	"atr_grab": "res://addons/combatdata/icons/atr_grab.svg",
	"atr_drop": "res://addons/combatdata/icons/atr_drop.svg",
	"atr_rush": "res://addons/combatdata/icons/atr_rush.svg",
}
const TEXT_HOLD: String = " (Hold)"

@export var identifier: StringName = &""

@export var moves: Array[WeaponMove] = []

## The [AnimationLibrary] used by this weapon. [br][br]
## If there is no animation library, then the weapon will use
## the [WeaponHandler]'s [AnimationMixer]'s animations.
@export var animation_library: AnimationLibrary = null

@export_group("Visuals")
@export var default_hit_effect: PackedScene = null
## Contains bone name and an additional transform for rotation and offset
@export var delay_visual_bones: Dictionary[StringName, Transform3D] = {}
@export_subgroup("Equip")
@export var weapon_mesh: Mesh = null
@export var equip_hide_hands: bool = false
@export var equip_hide_legs: bool = false
@export_subgroup("Holster", "holster_")
@export var holster_type: HolsterType = HolsterType.HIDE:
	set(value):
		holster_type = value
		notify_property_list_changed()

@export var holster_mesh: Mesh = null
@export var holster_bone: StringName = &""
@export var holster_bone_transform: Transform3D = Transform3D.IDENTITY
@export var holster_hide_hands: bool = false
@export var holster_hide_legs: bool = false
@export var holster_keep_previous: bool = false


func get_animation_library_name() -> StringName:
	# If there is no animation library, use the animations in the character's AnimationMixer.
	if !animation_library:
		return ""
	return identifier


func get_animation_list() -> Array[StringName]:
	if !animation_library:
		return []
	var anims: Array[StringName] = []
	for anim: StringName in animation_library.get_animation_list():
		anims.append("%s/%s" % [identifier, anim])

	return anims


func find_move(move_name: StringName) -> WeaponMove:
	var queue: Array[WeaponMove] = []
	queue.append_array(moves)

	while not queue.is_empty():
		var move: WeaponMove = queue.pop_front()

		if move.name == move_name:
			return move

		queue.append_array(move.next_moves)

	return null


func fix_move_animation_names_list(
	moves_list: Array[WeaponMove] = moves, recursive: bool = true
) -> void:
	for m: WeaponMove in moves_list:
		_fix_move_animation_name(m)
		if recursive:
			fix_move_animation_names_list(m.next_moves)


func _fix_move_animation_name(weapon_move: WeaponMove) -> void:
	if weapon_move.animation.is_empty():
		return
	weapon_move.animation = (
		"%s/%s" % [get_animation_library_name(), weapon_move.animation.get_slice("/", 1)]
	)


func _validate_property(property: Dictionary) -> void:
	match property.name:
		&"holster_bone", &"holster_bone_transform":
			if holster_type != HolsterType.BONE_ATTACHMENT_MESH:
				property.usage = PROPERTY_USAGE_NONE
		&"holster_mesh":
			if holster_type == HolsterType.HIDE:
				property.usage = PROPERTY_USAGE_NONE


static func _get_move_names(move: WeaponMove, array: PackedStringArray) -> void:
	array.append(move.name)
	for next_move: WeaponMove in move.next_moves:
		_get_move_names(next_move, array)
