extends EditorInspectorPlugin

func _can_handle(object: Object) -> bool:
	if object is WeaponTrack:
		return true
	return false


func _parse_property(
	object: Object, type: Variant.Type, name: String, hint: PropertyHint, hint_text: String,
	usage: int, wide: bool) -> bool:
	if name == "bone_name":
		if not EditorInterface.get_meta(&"combat_editor_visible", false):
			return false
		if not EditorInterface.has_meta(&"weapon_editor_scene"):
			return false
		var editor_scene: Node = EditorInterface.get_meta(&"weapon_editor_scene")
		if not is_instance_valid(editor_scene):
			return false
		var handler := WeaponHandler.try_get_handler(editor_scene)
		if not is_instance_valid(handler):
			return false
		hint = PROPERTY_HINT_ENUM_SUGGESTION
		hint_text = handler.skeleton.get_concatenated_bone_names()
		add_property_editor(
			name,
			EditorInspector.instantiate_property_editor(
				null,
				type,
				name,
				hint,
				hint_text,
				usage,
				wide
			)
		)
		return true

	return false
