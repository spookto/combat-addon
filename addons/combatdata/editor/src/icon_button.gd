@tool
extends Button

@export var icon_name: StringName = &"":
	set(value):
		icon_name = value
		icon = EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")

@export var min_size: float = 32.0:
	set(value):
		min_size = value
		custom_minimum_size = Vector2.ONE * min_size

var _tex: Texture2D = null

func _init() -> void:
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _ready() -> void:
	min_size = min_size
	icon_name = icon_name


func _validate_property(property: Dictionary) -> void:
	if ["icon", "icon_alignment", "vertical_icon_alignment", "expand_icon"].has(property.name):
		property.usage = PROPERTY_USAGE_NONE


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		icon_name = icon_name
