@tool
extends Control

const ADDITIONAL_TABS_OFFSET: int = 40

signal bone_selected(bone_index: int)
signal expand_state_changed(not_expanded: bool)

@export var additional_tabs: Dictionary[Control, StringName] = {}

var scene: Node:
	set(value):
		scene = value
		_handler = WeaponHandler.try_get_handler(scene)
		_set_selected_tab(_selected_tab)
var _selected_bone: int = -1:
	set(value):
		if _selected_bone == value:
			return
		_selected_bone = value
		bone_selected.emit(_selected_bone)

var _handler: WeaponHandler
var _scene_root: Node3D = null
var _selected_tab: int = 0:
	set = _set_selected_tab
var _tree_update_requests: int = 0
var _last_selected_node: NodePath

@onready var tab_bar: TabBar = %TabBar
@onready var tree: Tree = %Tree

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if not is_instance_valid(_scene_root):
			return
		if not is_node_ready():
			await ready
		for i: int in range(tab_bar.tab_count):
			var tab_id: int = tab_bar.get_tab_metadata(i)
			match tab_id:
				0:
					tab_bar.set_tab_icon(i, get_theme_icon(&"PackedScene", &"EditorIcons"))
				1:
					tab_bar.set_tab_icon(i, get_theme_icon(&"Bone", &"EditorIcons"))
				_:
					if tab_id >= ADDITIONAL_TABS_OFFSET:
						var tab_name: StringName = additional_tabs.values()[tab_id - ADDITIONAL_TABS_OFFSET]
						tab_bar.set_tab_icon(i, get_theme_icon(tab_name, &"EditorIcons"))
		%ExpandButton.icon = get_theme_icon(&"DistractionFree", &"EditorIcons")
		_set_selected_tab(_selected_tab)


func setup(scene_root: Node3D) -> void:
	_scene_root = scene_root
	_scene_root.child_order_changed.connect(func() -> void:
		if _selected_tab == 0:
			_set_selected_tab(0)
	)

	%ExpandButton.icon = get_theme_icon(&"DistractionFree", &"EditorIcons")
	%ExpandButton.theme_type_variation = &"FlatButton"
	%ExpandButton.toggle_mode = true
	%ExpandButton.toggled.connect(func(toggled_on: bool) -> void:
		expand_state_changed.emit(!toggled_on)
	)
	for i: int in range(additional_tabs.size()):
		_add_tab(additional_tabs.values()[i], ADDITIONAL_TABS_OFFSET + i)
	_add_tab("PackedScene", 0)
	_add_tab("Bone", 1)

	tab_bar.tab_selected.connect(func(tab_index: int) -> void:
		var tab_id: int = type_convert(tab_bar.get_tab_metadata(tab_index), TYPE_INT)
		_set_selected_tab(tab_id)
	)
	_set_selected_tab(tab_bar.get_tab_metadata(0))

	tree.item_selected.connect(_on_tree_item_selected)
	tree.item_collapsed.connect(_on_tree_item_collapsed)
	tree.nothing_selected.connect(func() -> void:
		tree.deselect_all()
		_selected_bone = -1
	)
	tree.button_clicked.connect(_on_tree_button_clicked)


func _add_tab(icon: String, id: int) -> void:
	tab_bar.add_tab("", get_theme_icon(icon, &"EditorIcons"))
	tab_bar.set_tab_metadata(tab_bar.tab_count - 1, id)


func _set_selected_tab(value: int) -> void:
	_selected_bone = -1
	tree.clear()

	tree.show()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_selected_tab = value
	additional_tabs.keys().all(func(tab: Control) -> bool:
		tab.hide()
		return true
	)

	match _selected_tab:
		0:
			_populate_tree_with_scene()
		1:
			_populate_tree_with_bones()
		_:
			if _selected_tab >= ADDITIONAL_TABS_OFFSET:
				tree.hide()
				size_flags_vertical = SIZE_FILL
				additional_tabs.keys()[_selected_tab - ADDITIONAL_TABS_OFFSET].show()


func _populate_tree_with_scene():
	_tree_update_requests = maxi(_tree_update_requests - 1, 0)
	if _tree_update_requests > 1:
		return
	if not is_instance_valid(_scene_root):
		return

	var root: TreeItem = tree.create_item()
	tree.hide_root = true

	for node: Node in _scene_root.get_children():
		_add_node_to_tree(node)


func _add_node_to_tree(node: Node, parent_tree_item: TreeItem = null) -> void:
	if _should_ignore_node(node):
		return

	var new_item: TreeItem = tree.create_item(parent_tree_item)
	new_item.set_text(0, node.name)
	new_item.set_icon(0, get_theme_icon(node.get_class(), &"EditorIcons"))
	new_item.set_metadata(0, node)
	new_item.collapsed = node.get_meta(&"combatdata_collapsed", false)
	if not is_instance_valid(node.get_owner()) and is_instance_valid(parent_tree_item):
		new_item.add_button(0, get_theme_icon(&"Remove", &"EditorIcons"), 10)
	if node is Node3D:
		new_item.add_button(0, _get_visible_icon(node.visible), 1)

	if _scene_root.get_path_to(node) == _last_selected_node:
		new_item.select(0)

	if not node.child_order_changed.is_connected(_queue_update_tree):
		node.child_order_changed.connect(_queue_update_tree)

	for child_node: Node in node.get_children():
		_add_node_to_tree(child_node, new_item)


func _queue_update_tree() -> void:
	if _selected_tab != 0:
		_tree_update_requests = 0
		return

	_tree_update_requests += 1
	_set_selected_tab.call_deferred(0)


func _should_ignore_node(node: Node) -> bool:
	if node.get_meta(&"_debug_hidden", false):
		return true
	elif node is CollisionShape3D or node is AnimationMixer:
		return true
	return false


func _populate_tree_with_bones():
	if not is_instance_valid(_handler):
		return
	if not is_instance_valid(_handler.skeleton):
		return

	var root: TreeItem = tree.create_item()
	tree.hide_root = true

	for index: int in _handler.skeleton.get_parentless_bones():
		_add_bone_to_tree(index, null)


func _add_bone_to_tree(bone_index: int, parent_tree_item: TreeItem = null) -> void:
	var new_item: TreeItem = tree.create_item(parent_tree_item)
	new_item.set_text(0, _handler.skeleton.get_bone_name(bone_index))
	new_item.set_metadata(0, bone_index)
	for index: int in _handler.skeleton.get_bone_children(bone_index):
		_add_bone_to_tree(index, new_item)


func _on_tree_item_selected() -> void:
	var item: TreeItem = tree.get_selected()
	if not is_instance_valid(item):
		return
	match _selected_tab:
		0:
			var node: Node = item.get_metadata(0)
			if is_instance_valid(node):
				_last_selected_node = _scene_root.get_path_to(node)
				EditorInterface.inspect_object(node)
		1:
			var bone_index: int = item.get_metadata(0)
			_selected_bone = bone_index


func _on_tree_item_collapsed(item: TreeItem) -> void:
	match _selected_tab:
		0:
			var node: Node = item.get_metadata(0)
			if is_instance_valid(node):
				node.set_meta(&"combatdata_collapsed", item.collapsed)


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return

	var btn_index: int = item.get_button_by_id(column, id)

	match _selected_tab:
		0:
			var node: Node = item.get_metadata(0)
			if is_instance_valid(node):
				match id:
					1:
						if node is Node3D:
							node.visible = !node.visible
							item.set_button(column, btn_index, _get_visible_icon(node.visible))
					10:
						node.queue_free()


func _get_visible_icon(value: bool) -> Texture2D:
	return get_theme_icon(
		&"GuiVisibilityVisible" if value else &"GuiVisibilityHidden",
		&"EditorIcons"
	)
