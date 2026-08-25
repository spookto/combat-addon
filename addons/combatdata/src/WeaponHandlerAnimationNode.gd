@tool
class_name WeaponHandlerAnimationNode
extends AnimationNodeExtension


func _process_animation_node(playback_info: PackedFloat64Array, test_only: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()

	var time: float = get_parameter(&"frame") / float(Engine.physics_ticks_per_second)
	time = maxf(time, 0.0)

	var tree_id: int = get_processing_animation_tree_instance_id()
	var tree_node: AnimationTree = instance_from_id(tree_id) as AnimationTree
	var anim: Animation = tree_node.get_animation(get_parameter(&"animation"))

	blend_animation(
		get_parameter(&"animation"),
		time,
		0.0,
		false,
		false,
		1.0,
		Animation.LOOPED_FLAG_NONE
	)

	# Length
	out.append(anim.length if anim else 0.0)
	# Time position
	out.append(time)
	# Delta
	out.append(playback_info[1])
	# Loop Mode
	out.append(0.0)
	# About to End
	out.append(0.0)
	# Infinite
	out.append(0.0)

	return out


func _get_parameter_list() -> Array:
	return [
		{
			"name": "animation",
			"type": TYPE_STRING,
		},
		{
			"name": "frame",
			"type": TYPE_INT,
		},
	]


func _get_parameter_default_value(parameter: StringName) -> Variant:
	if parameter == &"animation":
		return ""
	elif parameter == &"frame":
		return 0
	return null
