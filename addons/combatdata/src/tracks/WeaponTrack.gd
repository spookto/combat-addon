@tool
@abstract
class_name WeaponTrack
extends Resource

@export var start_frame: int = 0:
	set(value):
		start_frame = maxi(value, 0)
		emit_changed()

@export var debug_color := Color.TRANSPARENT:
	set(value):
		debug_color = value.clamp()
		emit_changed()

@abstract func get_duration() -> int
@abstract func compile() -> String
