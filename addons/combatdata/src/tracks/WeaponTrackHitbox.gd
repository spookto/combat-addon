@tool
class_name WeaponTrackHitBox
extends WeaponTrack

@export var bone_name: String
@export_custom(0, "suffix:m") var length: float = 1.0:
	set(value):
		length = maxf(value, 0.0)
@export_custom(0, "suffix:m") var radius: float = 0.5:
	set(value):
		value = minf(value, length * 0.5)
		radius = maxf(value, 0.0)
@export_custom(0, "suffix:m") var offset := Vector3.ZERO
@export_custom(0, "suffix:frames") var duration: int = 1:
	set(value):
		duration = maxi(value, 0)
		emit_changed()
@export var damage_index: int = 0:
	set(value):
		damage_index = maxi(value, 0)

func get_duration() -> int:
	return duration


func compile() -> String:
	return 'if frame == %d:\n\thandler.hit_area("%s", %s, %s, Vector3%s, %d).set_damage_index(%d)' % [
		start_frame,
		bone_name,
		length,
		radius,
		offset,
		duration,
		damage_index,
	]
