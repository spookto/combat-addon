extends EditorInspectorPlugin

const _DIR: String = "res://.godot/move_logic_scripts"
const _WEAPON_PATH_PREFIX: String = "#WEP_PATH:"

var plugin: EditorPlugin = null:
	set(value):
		plugin = value
		if is_instance_valid(plugin):
			plugin.resource_saved.connect(_on_resource_saved)


func _init() -> void:
	if not EditorInterface.has_user_signal(&"edit_move_script"):
		EditorInterface.add_user_signal(
			&"edit_move_script",
			[{
				"name": "move",
				"type": TYPE_OBJECT
			}]
		)

	EditorInterface.connect(&"edit_move_script", _edit_move_logic)
	if _DIR.begins_with("res://.godot/"):
		DirAccess.remove_absolute(_DIR)


func _can_handle(object: Object) -> bool:
	if object is WeaponMove:
		return true
	return false


func _parse_property(
	object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String,
	usage_flags: int, wide: bool) -> bool:

	if object is WeaponMove:
		if name == "logic":
			var hbox := HBoxContainer.new()
			var btn := Button.new()
			btn.text = "Edit Logic"
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_edit_move_logic.bind(object))

			var clear_btn := Button.new()
			clear_btn.text = "Force Refresh Logic"
			clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			clear_btn.pressed.connect(func() -> void:
				if _DIR.begins_with("res://.godot/"):
					DirAccess.remove_absolute(_DIR)
				_edit_move_logic(object)
			)

			hbox.add_child(btn)
			hbox.add_child(clear_btn)
			add_custom_control(hbox)

	return false


func _edit_move_logic(move: WeaponMove) -> void:
	var script: GDScript = null
	DirAccess.make_dir_recursive_absolute(_DIR)
	var move_path: String = ResourceUID.ensure_path(move.get_path())
	var path: String = move_path.get_basename().trim_prefix("res://").validate_filename()
	path = _DIR.path_join("%s_%s.gd" % [path, move.name])

	if ResourceLoader.exists(path):
		script = ResourceLoader.load(path)
	else:
		ResourceSaver.save(move.get_move_script(), path, ResourceSaver.FLAG_CHANGE_PATH)
		_edit_move_logic(move)
		return

	script.resource_name = move.name
	var move_code: String = move._get_move_code(false).replace("pass#", "")
	script.set_source_code(
		_WEAPON_PATH_PREFIX +  ResourceUID.path_to_uid(move_path) + "\n" + move_code
	)
	script.set_meta(&"source_move", move.get_path())

	EditorInterface.edit_script(script)


func _on_resource_saved(resource: Resource) -> void:
	if resource is GDScript:
		if not resource.source_code.begins_with(_WEAPON_PATH_PREFIX):
			return
		var move_path: String = resource.source_code.get_slice("\n", 0)
		move_path = move_path.trim_prefix(_WEAPON_PATH_PREFIX)

		if move_path.contains("::"):
			var base_resource := ResourceLoader.load(move_path.get_slice("::", 0))
			if base_resource:
				print(base_resource)
				EditorInterface.set_object_edited(base_resource, true)
				ResourceSaver.save(base_resource)
				base_resource.notify_property_list_changed()

		var move := ResourceLoader.load(move_path)#, "Resource", ResourceLoader.CACHE_MODE_IGNORE_DEEP)

		if not move:
			return

		var logic_code: String = resource.get_source_code()
		logic_code = logic_code.split("-> void:\n", true, 1)[1].dedent()
		move.logic = logic_code
		print(move.logic)
		EditorInterface.set_object_edited(move, true)
		EditorInterface.edit_resource(move)
		move.notify_property_list_changed()
