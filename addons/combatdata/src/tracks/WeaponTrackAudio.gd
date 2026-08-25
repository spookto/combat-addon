@tool
class_name WeaponTrackAudio
extends WeaponTrack

@export var stream: AudioStream
@export var allow_overlap: bool = false
@export var stop_with_move: bool = false
@export var pitch_scale: float = 1.0
@export_custom(0, "suffix:dB") var volume_db: float = 0.0

func get_duration() -> int:
	if not is_instance_valid(stream):
		return 0
	return ceili((stream.get_length() / pitch_scale) * Engine.physics_ticks_per_second)


func compile() -> String:
	var out: String = "if frame == %d:\n\tprint('Audio Not Implemented Yet')" % start_frame
	return out
