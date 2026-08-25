@tool
extends Control

func _draw() -> void:
	draw_style_box(
		get_theme_stylebox(&"child_bg", &"EditorProperty"),
		Rect2(Vector2.ZERO, get_size())
	)
