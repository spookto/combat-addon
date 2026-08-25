@tool
extends EditorPlugin

const SETTINGS_NAME: String = "addons/combat_addon/settings_path"
const SETTINGS_DEFAULT: String = "res://addons/combatdata/default_settings.tres"
const MainPanel: = preload("./editor/scenes/combatdata_main.tscn")
const ICON: DPITexture = preload("./icon.svg")

var move_inspector := preload("./editor/src/weapon_move_inspector.gd").new()
var tracks_inspector := preload("./editor/src/weapon_tracks_inspector.gd").new()
var main_panel_instance: Node

func _enter_tree() -> void:
	if not ProjectSettings.has_setting(SETTINGS_NAME):
		ProjectSettings.set_setting(SETTINGS_NAME, SETTINGS_DEFAULT)
	ProjectSettings.add_property_info({
		"name": SETTINGS_NAME,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE_PATH,
		"hint_string": "*.tres,*.res"
	})
	ProjectSettings.set_as_basic(SETTINGS_NAME, true)

	move_inspector.plugin = self
	add_inspector_plugin(move_inspector)
	add_inspector_plugin(tracks_inspector)

	main_panel_instance = MainPanel.instantiate()
	main_panel_instance.plugin = self
	EditorInterface.get_editor_main_screen().add_child.call_deferred(main_panel_instance)
	_make_visible(false)


func _exit_tree() -> void:
	remove_inspector_plugin(move_inspector)
	remove_inspector_plugin(tracks_inspector)

	if is_instance_valid(main_panel_instance):
		main_panel_instance.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(main_panel_instance):
		main_panel_instance.visible = visible
		EditorInterface.set_meta(&"combat_editor_visible", visible)


func _get_plugin_name() -> String:
	return "Combat"


func _get_plugin_icon() -> Texture2D:
	var mono_color := EditorInterface.get_editor_theme().get_color(&"mono_color", &"Editor")
	if mono_color.v < 0.5:
		var icon_light := ICON.duplicate()
		icon_light.color_map = {
			Color.html("e0e0e0"): Color.html("5a5a5a"),
			Color.html("b4b4b4"): Color.html("363636"),
		}
		return icon_light
	return ICON
