@tool
class_name WeaponTrackMovement
extends WeaponTrack

@export_enum("None:-1", "Global", "Local", "Impulse", "Local Impulse") var type: int = 0
@export var velocity: Vector3
@export var multiply_velocity_by_delta: bool = false

@export_group("Drag", "drag")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var drag_enabled: bool = false
@export_custom(0, "suffix:m/s²") var drag_amount: float = 0.0
@export var drag_horizontal_only: bool = true
@export_custom(0, "suffix:frames") var duration: int = 1:
	set(value):
		duration = maxi(value, 0)
		emit_changed()
@export var infinite: bool = false:
	set(value):
		infinite = value
		emit_changed()

func get_duration() -> int:
	if infinite:
		return -10
	return duration


func compile() -> String:
	var vel: Vector3 = velocity
	if multiply_velocity_by_delta:
		vel = velocity / Engine.physics_ticks_per_second

	var out: String = ""
	match type:
		0:
			out += "handler.velocity = Vector3%s" % vel
		1:
			out += "handler.velocity = handler.global_basis * Vector3%s" % vel
		2:
			out += "handler.velocity += Vector3%s" % vel
		3:
			out += "handler.velocity += handler.global_basis * Vector3%s" % vel
		_:
			pass
	if drag_enabled:
		if not out.is_empty():
			out += "\n"
		out += "handler.velocity = handler.velocity.move_toward(handler.velocity * Vector3%s, %f)" % [
			"(0.0, 1.0, 0.0)" if drag_horizontal_only else ".ZERO",
			(drag_amount / Engine.physics_ticks_per_second)
		]
	var cond: String = "if frame >= %d" % start_frame
	if not infinite:
		cond += (" and frame <= %d" % (start_frame + duration))
	return "%s:\n%s" % [cond, out.indent("\t")]
