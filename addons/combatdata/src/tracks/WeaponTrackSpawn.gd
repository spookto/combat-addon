@tool
class_name WeaponTrackSpawn
extends WeaponTrack

@export_enum("Transform", "Bone") var spawn_at: int = 0:
	set(value):
		spawn_at = value
		notify_property_list_changed()
@export var use_move_spawnables: bool = true:
	set(value):
		use_move_spawnables = value
		notify_property_list_changed()
@export var scene: PackedScene
@export var spawn_index: int = 0
@export var transform := Transform3D.IDENTITY
@export var transform_local: bool = true
@export var bone_name: String = ""
@export var bone_offset := Vector3.ZERO

func get_duration() -> int:
	return 0


func compile() -> String:
	var out: String = ""
	var spawn_info: String = ""
	if use_move_spawnables:
		spawn_info = "move.spawnables[%d]" % spawn_index
	else:
		spawn_info = '"%s"' % scene.resource_path
	match spawn_at:
		0:
			out = "print('Spawn Not Implemented Yet')"
		1:
			out = "handler.spawn_at_bone(%s, %s, Vector3%s)" % [
				spawn_info,
				bone_name,
				bone_offset,
			]
	return ("if frame == %d:\n" % start_frame) + out.indent("\t")


func _transform_to_string(t: Transform3D) -> String:
	return "%sTransform3D(Vector3%s, Vector3%s, Vector3%s, Vector3%s)" % [
		"character.get_global_transform() * " if transform_local else "",
		t.basis.x,
		t.basis.y,
		t.basis.z,
		t.origin,
	]


func _validate_property(property: Dictionary) -> void:
	if property.name == &"scene" and use_move_spawnables:
		property.usage = PROPERTY_USAGE_NONE
	elif property.name == &"spawn_index" and not use_move_spawnables:
		property.usage = PROPERTY_USAGE_NONE

	if (property.name == &"transform" or property.name == &"transform_local") and spawn_at != 0:
		property.usage = PROPERTY_USAGE_NONE
	elif (property.name == &"bone_name" or property.name == &"bone_offset") and spawn_at == 0:
		property.usage = PROPERTY_USAGE_NONE
