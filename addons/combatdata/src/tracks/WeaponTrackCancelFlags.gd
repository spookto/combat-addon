@tool
class_name WeaponTrackCancelFlags
extends WeaponTrack

@export var flags: Array[WeaponHandler.Cancel] = []

func get_duration() -> int:
	return 0


func compile() -> String:
	return "if frame == %d:\n\thandler.set_cancel_flags(%s)" % [
		start_frame,
		str(flags)
	]
