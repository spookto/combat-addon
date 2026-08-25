@tool
extends HBoxContainer

const SAVE_PATH: String = "res://.godot/combatdata.cfg"

signal character_scene_selected(scene_path: String)
signal character_reload_requested

var _tabbar: TabBar
var _setup_complete: bool = false

func _exit_tree() -> void:
	if not _setup_complete:
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not save_file:
		print(FileAccess.get_open_error())
		return
	save_file.store_string("\n".join(_get_opened_scenes()))
	save_file.flush()
	save_file.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if not is_node_ready():
			await ready
		if is_instance_valid(_tabbar):
			for i: int in range(_tabbar.tab_count):
				var scene_path: String = _tabbar.get_tab_metadata(i)
				if scene_path.get_extension() == "tscn":
					var scene: PackedScene = load(scene_path) as PackedScene
					_tabbar.set_tab_icon(
						i,
						get_theme_icon(scene.get_state().get_node_type(0), &"EditorIcons")
					)


func setup() -> void:
	_setup_complete = true

	_tabbar = TabBar.new()
	_tabbar.theme_type_variation = &"TabBarInner"
	_tabbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabbar.tab_close_pressed.connect(_close_tab)
	_tabbar.drag_to_rearrange_enabled = true
	_tabbar.tab_changed.connect(func(idx: int) -> void:
		if not _tabbar.get_tab_metadata(idx):
			return
		var path: String = _tabbar.get_tab_metadata(idx)
		character_scene_selected.emit(path)
	)
	add_child(_tabbar)

	var quick_load := create_button(&"Add")
	quick_load.pressed.connect(func() -> void:
		EditorInterface.popup_quick_open(_add_scene_path_tab, [&"PackedScene"])
	)
	add_child(quick_load)

	var reload := create_button(&"Reload")
	reload.pressed.connect(character_reload_requested.emit)
	add_child(reload)

	_load_saved()

	var open_scenes := _get_opened_scenes()
	if not open_scenes.is_empty():
		character_scene_selected.emit(open_scenes[0])


func create_button(icon: StringName) -> Button:
	var btn := Button.new()
	btn.icon = EditorInterface.get_editor_theme().get_icon(icon, &"EditorIcons")
	btn.theme_type_variation = &"FlatButton"
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.theme_changed.connect(func() -> void:
		btn.icon = EditorInterface.get_editor_theme().get_icon(icon, &"EditorIcons")
	)
	return btn


func add_scene_tab(scene: Node) -> void:
	_add_scene_path_tab(scene.scene_file_path)


func get_current_scene() -> String:
	if _tabbar.current_tab < 0:
		return ""
	return _tabbar.get_tab_metadata(_tabbar.current_tab)


func _add_scene_path_tab(scene_path: String) -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return

	if _get_opened_scenes().has(scene_path):
		return

	var scene: PackedScene = load(scene_path) as PackedScene
	_tabbar.add_tab(
		scene_path.get_file().get_basename(),
		get_theme_icon(scene.get_state().get_node_type(0), &"EditorIcons")
	)
	_tabbar.set_tab_metadata(
		_tabbar.tab_count - 1,
		scene_path
	)

	# Open this tab if it is the first one
	if _tabbar.tab_count == 1:
		character_scene_selected.emit(scene_path)

	# Update close button policy
	_close_tab(-1)


func _load_saved() -> void:
	if not _setup_complete:
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not save_file:
		print(FileAccess.get_open_error())
		return
	for scene: String in save_file.get_as_text().split("\n", false):
		_add_scene_path_tab(scene)
	save_file.close()


func _close_tab(index: int) -> void:
	if _tabbar.tab_count <= 1:
		return
	if index >= 0:
		var path: String = _tabbar.get_tab_metadata(index)
		_tabbar.remove_tab(index)
	if _tabbar.tab_count > 1:
		_tabbar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	else:
		_tabbar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER


func _get_opened_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in range(_tabbar.tab_count):
		out.append(_tabbar.get_tab_metadata(i))
	return out
