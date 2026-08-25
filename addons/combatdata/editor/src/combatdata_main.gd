@tool
extends Control

signal character_loaded
signal weapon_loaded
signal move_selected(move: WeaponMove, handler: WeaponHandler)

const CombatdataFrameTimeline = preload("uid://d4i01nwccvyha")
const CombatdataToolbar = preload("uid://b2aaac35hy2yv")
const CombatdataMoveEditor = preload("uid://ddj0gq7bpi3ej")
const CombatdataInspectorTree = preload("uid://8b8o30mhm10b")

var plugin: EditorPlugin

var _character_scene: Node3D:
	set(value):
		_character_scene = value
		_reset_saved_states()
		EditorInterface.set_meta(&"weapon_editor_scene", _character_scene)
		inspector_tree_container.scene = _character_scene

var _current_weapon: WeaponInformation:
	set(value):
		_current_weapon = value

		var is_valid: bool = (_current_weapon != null)

		%MoveAdd.disabled = !is_valid
		%MoveRefresh.disabled = !is_valid
		%MoveLinkedChild.disabled = !is_valid

		moves_container.visible = is_valid
		edit_container.visible = is_valid

		if !is_valid:
			weapon_path.text = ""
			_current_move = null
			return

		weapon_path.text = _current_weapon.resource_path

		if is_instance_valid(_weapon_handler):
			_weapon_handler.information = _current_weapon
			root_3d.propagate_call(&"editor_update_visibility")

		_animation_library_file_selected(_current_weapon.animation_library.resource_path if _current_weapon.animation_library else "")
var _current_move: WeaponMove:
	set(value):
		_current_move = value
		var is_valid: bool = (_current_move != null)
		if is_instance_valid(move_editor):
			move_editor.edit_move(_current_move)

		%MoveAddChild.disabled = !is_valid
		%MoveRemove.disabled = !is_valid
		%MoveUp.disabled = !is_valid
		%MoveDown.disabled = !is_valid

var _weapon_handler: WeaponHandler:
	set(value):
		_weapon_handler = value
		frame_timeline.weapon_handler = _weapon_handler

var _current_anim: AnimationMixer
var _added_moves: Array[WeaponMove] = []
var _attack_hold_group: ButtonGroup = null
var _simulating_move: bool = false:
	set(value):
		_simulating_move = value
		if is_instance_valid(_character_scene):
			_character_scene.set_meta(&"_no_spawns", value)
var _remap_button_icons: Dictionary[Button, StringName] = {}
var _icon_visible: Texture2D
var _icon_hidden: Texture2D
var _icon_linked: Texture2D
var _setup_complete: bool = false
var _state_handler_hit_toggles: Array[Button] = []
var _color_highlight := Color.WHITE

@onready var frame_box: Range = %FrameBox
@onready var frame_timeline: CombatdataFrameTimeline = %FrameSlider

@onready var edit_container = %BehaviorEditor

@onready var weapon_path: LineEdit = %WeaponPath
@onready var weapon_button:= %WeaponButton
@onready var weapon_dialog: EditorFileDialog
@onready var moves_container = %MovesContainer
@onready var move_tree: Tree = %MoveTree

@onready var root_3d: Node3D = %Root3D

@onready var animation_button: OptionButton = %AnimationButton

@onready var toolbar: CombatdataToolbar = %Toolbar
@onready var move_editor: CombatdataMoveEditor = %MoveEditor
@onready var scene_container: SubViewportContainer = %SceneSubviewport
@onready var attack_inputs_container := %AttackInputsContainer
@onready var inspector_tree_container: CombatdataInspectorTree = %InspectorTreeContainer

#region Setup
func _ready() -> void:
	if get_tree().edited_scene_root == self:
		return
	_setup_complete = true

	scene_container.draw.connect(_on_scene_container_draw)
	get_tree().node_added.connect(_on_tree_node_added)

	%StartButton.shortcut = _quick_shortcut(KEY_SPACE, true)

	# Setup root position editor
	var offset_spin_box := %OffsetSpinBox
	var reset_button := Button.new()
	reset_button.theme_type_variation = &"FlatButton"
	reset_button.icon = get_theme_icon("Reload", "EditorIcons")
	_remap_button_icons[reset_button] = &"Reload"
	reset_button.hide()
	reset_button.pressed.connect(func() -> void:
		offset_spin_box.value = Vector3.ZERO
		reset_button.hide()
	)
	%OffsetLabelContainer.add_child(reset_button)
	offset_spin_box.value_changed.connect(func(value: Vector3) -> void:
		root_3d.position = value
		reset_button.show()
	)

	# Setup root rotation editor
	var rotate_spinbox := EditorSpinSlider.new()
	reset_button = reset_button.duplicate()
	reset_button.pressed.connect(func() -> void:
		rotate_spinbox.value = 0.0
		reset_button.hide()
	)
	%RotateLabelContainer.add_child(reset_button)
	rotate_spinbox.min_value = 0.0
	rotate_spinbox.max_value = 360.0
	rotate_spinbox.suffix = "°"
	rotate_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_spinbox.value_changed.connect(func(value: float) -> void:
		root_3d.rotation_degrees.y = value
		reset_button.show()
	)
	%Rotate.add_child(rotate_spinbox)

	# Setup ground height editor
	reset_button = reset_button.duplicate()
	reset_button.pressed.connect(func() -> void:
		if is_instance_valid(_character_scene):
			state_ground_height.value = 0.0
		else:
			state_ground_height.value = 0.0
		reset_button.hide()
	)
	%GroundHeightLabelContainer.add_child(reset_button)
	state_ground_height.value_changed.connect(reset_button.show.unbind(1))
	%GroundHeightContainer.add_child(state_ground_height)
	state_ground_height.allow_greater = true
	state_ground_height.hide_slider = true
	state_ground_height.step = 0.01
	state_ground_height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_ground_height.suffix = "m"

	# Setup handler state editor
	var handler_state_container := %HandlerStateContainer
	var hit_landed_checkbox := CheckBox.new()
	hit_landed_checkbox.text = "Hit Landed"
	var hit_poise_broke_checkbox := hit_landed_checkbox.duplicate()
	hit_poise_broke_checkbox.text = "Poise Broke"
	var hit_grab_success_checkbox := hit_landed_checkbox.duplicate()
	hit_grab_success_checkbox.text = "Grab Success"
	hit_landed_checkbox.toggled.connect(func(toggled_on: bool) -> void:
		hit_poise_broke_checkbox.disabled = not toggled_on
		hit_grab_success_checkbox.disabled = not toggled_on
	)
	hit_landed_checkbox.toggled.emit(hit_landed_checkbox.is_pressed())
	handler_state_container.add_child(hit_landed_checkbox)
	handler_state_container.add_child(hit_poise_broke_checkbox)
	handler_state_container.add_child(hit_grab_success_checkbox)
	_state_handler_hit_toggles.append_array(handler_state_container.get_children())

	# Setup scene and weapon tabs toolbar
	toolbar.character_scene_selected.connect(_character_selected)
	toolbar.character_reload_requested.connect(func() -> void:
		var load_wep: String = ""
		_character_selected(toolbar.get_current_scene())
		if not load_wep.is_empty():
			_weapon_selected(load_wep)
	)
	toolbar.setup()

	move_editor.setup()
	move_editor.update_tree_requested.connect(update_move_tree_item)

	inspector_tree_container.setup(root_3d)
	inspector_tree_container.bone_selected.connect(func(bone_index: int) -> void:
		set_meta(&"selected_bone", bone_index)
		scene_container.queue_redraw()
	)

	# Frame time slider
	frame_timeline.setup()
	frame_box.share(frame_timeline)
	frame_box.value_changed.connect(func(value: int) -> void:
		_seek_frame(value)
		_on_pause_button_pressed()
	)

	# Time Scale button
	var time_scale_button: Button = %TimeScaleButton
	var time_scale_popup := PopupPanel.new()
	var time_scale_hbox := HBoxContainer.new()
	var time_scale_slider := HSlider.new()
	var time_scale_reset := Button.new()
	time_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_scale_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	time_scale_slider.min_value = 0.1
	time_scale_slider.max_value = 4.0
	time_scale_slider.step = 0.1
	time_scale_button.icon = get_theme_icon(&"Time", &"EditorIcons")
	_remap_button_icons[time_scale_button] = &"Time"
	time_scale_button.add_child(time_scale_popup)
	time_scale_button.pressed.connect(func() -> void:
		var pos: Vector2 = time_scale_button.get_screen_position()
		pos.y += time_scale_button.size.y
		time_scale_popup.popup(Rect2(pos, Vector2.RIGHT * 160.0))
	)
	time_scale_reset.flat = true
	time_scale_reset.icon = get_theme_icon(&"Reload", &"EditorIcons")
	_remap_button_icons[time_scale_reset] = &"Reload"
	time_scale_reset.disabled = true
	time_scale_reset.pressed.connect(time_scale_slider.set_value.bind(1.0))
	time_scale_slider.value_changed.connect(func(value: float) -> void:
		time_scale_button.text = "%.1f×" % value
		if is_instance_valid(_weapon_handler):
			_weapon_handler.speed_scale = value
		time_scale_reset.disabled = is_equal_approx(value, 1.0)
	)

	time_scale_hbox.add_child(time_scale_slider)
	time_scale_hbox.add_child(time_scale_reset)
	time_scale_popup.add_child(time_scale_hbox)

	time_scale_slider.set_value(1.0)

	var copy_move_list: Button = %CopyMoveListPreview
	copy_move_list.icon = get_theme_icon(&"ActionCopy", &"EditorIcons")
	_remap_button_icons[copy_move_list] = &"ActionCopy"
	copy_move_list.modulate.a = 0.4
	copy_move_list.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(%MovePreviewText.text)
	)

	var move_list_zoom_slider: Range = %MoveListZoomSlider
	move_list_zoom_slider.min_value = 1
	move_list_zoom_slider.max_value = 3
	move_list_zoom_slider.step = 0.1
	move_list_zoom_slider.value_changed.connect(func(value: float) -> void:
		%MovePreviewText.add_theme_font_size_override(
			&"normal_font_size", get_theme_font_size(&"normal_font_size", &"RichTextLabel") * value
		)
	)
	%MoveListZoomIcon.theme_changed.connect(func() -> void:
		%MoveListZoomIcon.texture = get_theme_icon(&"Zoom", &"EditorIcons")
	)
	%MoveListZoomIcon.theme_changed.emit()
	%MovePreviewDialog.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

	if is_instance_valid(plugin):
		# Add newly opened scenes if they are a GameCharacter
		plugin.scene_changed.connect(func(scene_root: Node) -> void:
			if not is_instance_valid(scene_root):
				return
			if is_instance_valid(WeaponHandler.try_get_handler(scene_root)):
				toolbar.add_scene_tab(scene_root)
		)

		# Add currently open scene if it is a GameCharacter
		var open_scene: Node = EditorInterface.get_edited_scene_root()
		if is_instance_valid(WeaponHandler.try_get_handler(open_scene)):
			toolbar.add_scene_tab(open_scene)

	print("combatdata_main.gd: Initializing")
	_current_weapon = _current_weapon
	_current_move = _current_move

	move_tree.item_selected.connect(_on_move_tree_item_selected)
	move_tree.button_clicked.connect(_on_move_tree_button_clicked)
	move_tree.nothing_selected.connect(move_tree.deselect_all)

	weapon_dialog = _create_dialog("WeaponInformation")
	weapon_button.pressed.connect(weapon_dialog.popup_centered)
	weapon_dialog.file_selected.connect(_weapon_selected)
	%WeaponReloadButton.pressed.connect(func() -> void:
		_weapon_selected(get_meta(&"current_weapon_path", ""))
		)
	%EditWeapon.pressed.connect(func() -> void:
		if not _current_weapon:
			return
		EditorInterface.inspect_object(_current_weapon, "", true)
	)

	%SceneBottom.propagate_call(&"set_text_overrun_behavior", [TextServer.OVERRUN_TRIM_CHAR])

	animation_button.get_popup().about_to_popup.connect(_populate_animations_list)
	animation_button.item_selected.connect(_on_animation_selected)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if not is_node_ready():
			await ready
		if not _setup_complete:
			return
		_icon_visible = get_theme_icon(&"GuiVisibilityVisible", &"EditorIcons")
		_icon_hidden = get_theme_icon(&"GuiVisibilityHidden", &"EditorIcons")
		_icon_linked = get_theme_icon(&"Instance", &"EditorIcons")

		for button: Button in _remap_button_icons:
			button.icon = get_theme_icon(_remap_button_icons[button], &"EditorIcons")

		_color_highlight = get_theme_color(&"accent_color", &"Editor").lerp(
			get_theme_color(&"mono_color", &"Editor").inverted(),
			0.5
		)
		_color_highlight.a = 0.5

		update_move_tree.call_deferred()


func _create_dialog(type: String = "") -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.size = Vector2(800,600)

	if not type.is_empty():
		for extension: String in ResourceLoader.get_recognized_extensions_for_type(type):
			dialog.add_filter("*." + extension, extension.to_upper())

	add_child(dialog)
	return dialog

#endregion


#region Component Selection
func _weapon_selected(path: String):
	set_meta(&"current_weapon_path", path)
	if path.is_empty():
		return

	update_move_tree.call_deferred()
	var weapon = load(path) as WeaponInformation
	_current_weapon = weapon
	_current_move = null

	weapon_loaded.emit()

	if !weapon:
		printerr("CombatData: Selected Resource is not of type WeaponInformation")
		return


func _character_selected(path: String):
	set_meta(&"already_selected_weapon", false)
	set_meta(&"current_character_path", path)
	move_selected.emit(null, null)
	if path.is_empty():
		return

	%Camera3D.make_current.call_deferred()

	for c in root_3d.get_children():
		c.queue_free()
	animation_button.clear()

	var character: PackedScene = load(path) as PackedScene

	character_loaded.emit()

	if not is_instance_valid(character):
		return

	var success: bool = await set_character(character)
	%Content.visible = success
	if not success:
		return


func set_character(character_scene: PackedScene) -> bool:
	if is_instance_valid(_character_scene):
		_character_scene.get_parent().remove_child(_character_scene)
		_character_scene.queue_free()
		_weapon_handler = null
		_current_anim = null

	if not _is_scene_character(character_scene):
		_character_scene = null
		return false

	_character_scene = character_scene.instantiate()
	root_3d.add_child(_character_scene)
	_character_scene.position.y = 0.0

	_weapon_handler = WeaponHandler.try_get_handler(_character_scene)
	if not is_instance_valid(_weapon_handler):
		_character_scene.queue_free()
		return false

	var inputs_count: int = 2
	move_editor.set_extra_input_count(0)
	inputs_count += 0

	for child: Node in attack_inputs_container.get_children():
		child.queue_free()

	if not is_instance_valid(_attack_hold_group):
		_attack_hold_group = ButtonGroup.new()
		_attack_hold_group.allow_unpress = true
		_attack_hold_group.pressed.connect(func(pressed_button: BaseButton) -> void:
			if not is_instance_valid(_weapon_handler):
				return
			#TODO Add attack hold debugging
			#if not pressed_button.is_pressed():
				#_weapon_handler.debug_attack_input = 0
				#return
			#_weapon_handler.debug_attack_input = pressed_button.get_meta(&"hold", 0)
		)

	for i: int in range(inputs_count):
		var container := HBoxContainer.new()
		container.add_theme_constant_override(&"separation", 0)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var hold := CheckBox.new()
		hold.button_group = _attack_hold_group
		hold.tooltip_text = "Hold"
		hold.set_meta(&"hold", i + 1)
		container.add_child(hold)
		var press := Button.new()
		press.alignment = HORIZONTAL_ALIGNMENT_LEFT
		press.theme_type_variation = &"FlatButton"
		press.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		press.size_flags_vertical = Control.SIZE_EXPAND_FILL
		press.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
		press.pressed.connect(func() -> void:
			if not is_instance_valid(_weapon_handler):
				return
			_weapon_handler.attack_input(i)
		)
		match i:
			0:
				press.text = "Light"
				press.shortcut = _quick_shortcut(KEY_Z)
			1:
				press.text = "Heavy"
				press.shortcut = _quick_shortcut(KEY_X)
			_:
				press.text = "Extra %d" % (i - 1)

		# Hold is activated by holding shift along with shortcut
		if is_instance_valid(press.shortcut):
			var event: InputEvent = press.shortcut.events[0]
			if event is InputEventKey:
				hold.shortcut = _quick_shortcut(event.physical_keycode, true)

		container.add_child(press)
		attack_inputs_container.add_child(container)

	for child: Node in _character_scene.get_children():
		if child is CanvasLayer:
			child.hide()

	_current_anim = _weapon_handler.animation_tree as AnimationMixer

	if not _weapon_handler.frame_processed.is_connected(_on_weapon_handler_frame_processed):
		_weapon_handler.frame_processed.connect(_on_weapon_handler_frame_processed)
	if not _weapon_handler.move_started.is_connected(_on_weapon_handler_move_started):
		_weapon_handler.move_started.connect(_on_weapon_handler_move_started)
	if not _weapon_handler.move_stopped.is_connected(_on_weapon_handler_move_stopped):
		_weapon_handler.move_stopped.connect(_on_weapon_handler_move_stopped)

	if is_instance_valid(_weapon_handler.active_information):
		_weapon_selected.bind(
			_weapon_handler.active_information.resource_path
			).call_deferred()
	elif not get_meta(&"already_selected_weapon", false):
		_current_weapon = null

	state_ground_height.value = 0.0

	return true


func _is_scene_character(scene: PackedScene) -> bool:
	var scene_state := scene.get_state()
	if scene_state.get_node_type(0) != &"CharacterBody3D":
		return false
	return true

	## Get script from scene state
	#var script: Script = null
	#for i: int in range(scene_state.get_node_property_count(0)):
		#if scene_state.get_node_property_name(0, i) == &"script":
			#script = scene_state.get_node_property_value(0, i)
			#break
#
	#var iteration_limit: int = 10
	#while iteration_limit > 0:
		#if not script:
			#return false
#
		#iteration_limit -= 1
		## Keep checking if this script inherits GameCharacter
		#if script == GameCharacter:
			#return true
		#script = script.get_base_script()
#
	#return false

#endregion


#region Move Tree
func update_move_tree() -> void:
	_added_moves = []
	move_tree.clear()
	var root = move_tree.create_item()
	move_tree.hide_root = true

	if !_current_weapon:
		return

	for move: WeaponMove in _current_weapon.moves:
		_add_moves(move)
	_update_tree_linked_count.call_deferred()


func update_move_tree_item(tree_item: TreeItem = move_tree.get_selected()) -> void:
	if !tree_item:
		for child: TreeItem in move_tree.get_root().get_children():
			update_move_tree_item(child)
		return

	var move: WeaponMove = tree_item.get_metadata(0) as WeaponMove
	if !move:
		return

	var parent_input: String = (tree_item.get_parent().get_text(1) + " ") if tree_item.get_parent() != move_tree.get_root() else ""
	var input: String = parent_input

	tree_item.set_icon(1, null)
	match move.input:
		WeaponMove.MoveInput.NONE:
			input += "-"
		WeaponMove.MoveInput.LIGHT:
			input += "L"
		WeaponMove.MoveInput.HEAVY:
			input += "H"
		_:
			input += "E%d" % (move.input + 1 - WeaponMove.MoveInput.EXTRA_1)

	tree_item.set_text(0, move.name)
	tree_item.set_text(1, input)
	tree_item.set_text(2, move.get_condition_text())

	if tree_item.get_child_count() == 0:
		return
	for child: TreeItem in tree_item.get_children():
		update_move_tree_item(child)


func _add_moves(weapon_move: WeaponMove, parent_tree_item: TreeItem = null) -> void:
	var new_move_item:= move_tree.create_item(parent_tree_item)
	new_move_item.set_metadata(0, weapon_move)
	update_move_tree_item(new_move_item)

	_added_moves.append(weapon_move)
	move_tree.set_column_expand(move_tree.columns - 1, false)
	var linked_color := get_theme_color(&"mono_color", &"Editor")
	linked_color.a = 0.4
	if _added_moves.count(weapon_move) > 1:
		for i: int in range(move_tree.columns):
			new_move_item.set_custom_color(i, linked_color)
			new_move_item.set_icon_modulate(i, linked_color)
		new_move_item.set_meta(&"linked", true)
		return

	_move_add_visibility_button(new_move_item)
	for next_move: WeaponMove in weapon_move.next_moves:
		_add_moves(next_move, new_move_item)


func _move_add_visibility_button(move_item: TreeItem) -> void:
	move_item.add_button(move_tree.columns - 1, _icon_visible)
	move_item.set_button_tooltip_text(move_tree.columns - 1, 0, "Toggle Visibility")
	_move_update_visibility_button(move_item)


func _move_update_visibility_button(move_item: TreeItem) -> void:
	var weapon_move: WeaponMove = move_item.get_metadata(0) as WeaponMove
	if !weapon_move:
		return

	move_item.set_button(move_tree.columns-1, 0, _icon_hidden if weapon_move.hidden else _icon_visible)


func _on_move_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if column == 0:
		return
	var weapon_move: WeaponMove = item.get_metadata(0) as WeaponMove
	if !weapon_move:
		return

	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Set move hidden", UndoRedo.MERGE_DISABLE, weapon_move)
	ur.add_do_property(weapon_move, &"hidden", not weapon_move.hidden)
	ur.add_undo_property(weapon_move, &"hidden", weapon_move.hidden)
	ur.add_do_method(EditorInterface, &"set_object_edited", weapon_move, true)
	ur.add_undo_method(EditorInterface, &"set_object_edited", weapon_move, true)
	ur.add_do_method(self, &"_move_update_visibility_button", item)
	ur.add_undo_method(self, &"_move_update_visibility_button", item)
	ur.commit_action()


func _on_move_tree_item_selected() -> void:
	var weapon_move: WeaponMove = move_tree.get_selected().get_metadata(0) as WeaponMove

	var item := move_tree.get_root()
	var linked_highlight_color := get_theme_color(&"mono_color", &"Editor")
	linked_highlight_color.a = 0.1
	while item.get_next_in_tree() != null:
		item = item.get_next_in_tree()
		if item == move_tree.get_selected():
			continue
		if item.get_metadata(0) == weapon_move:
			for i: int in range(move_tree.columns):
				item.set_custom_bg_color(i, linked_highlight_color)
				item.set_meta(&"bg_color", linked_highlight_color)
		else:
			for i: int in range(move_tree.columns):
				item.clear_custom_bg_color(i)
				item.remove_meta(&"bg_color")

	if weapon_move == _current_move:
		EditorInterface.inspect_object(_current_move)
	_current_move = weapon_move
	_weapon_handler.stop_move()
	move_selected.emit(weapon_move, _weapon_handler)
	frame_box.set_value_no_signal(0)
	frame_timeline.clear_transitions()
	if _current_move.logic.is_empty():
		frame_box.max_value = 0
		frame_timeline.clear_all()

	if !weapon_move:
		return

	if _weapon_handler:
		_weapon_handler.information = _current_weapon

	(func() -> void:
		_simulate_new_move(200, true)
		_weapon_handler.start_move(weapon_move)
		_weapon_handler.pause_move()
		if not saved_states.is_empty():
			_on_reset_character_position_pressed()
	).call_deferred()
	animation_button.select(-1)
	for i in range(animation_button.item_count):
		if animation_button.get_item_text(i) == _current_move.animation:
			animation_button.select(i)
			_update_frame_time_limit()
			break


func _on_animation_selected(index: int) -> void:
	if index < 0:
		return
	if !_current_move || !_current_weapon:
		return

	_current_move.animation = animation_button.get_item_text(index)
	_update_frame_time_limit()

#endregion

#region Animation Library
func _animation_library_file_selected(path: String) -> void:
	if !is_instance_valid(_current_weapon):
		return

	if path.is_empty():
		_current_weapon.animation_library = null
		_populate_animations_list()
		return

	var library: AnimationLibrary = load(path) as AnimationLibrary
	if !library:
		_current_weapon.animation_library = null
		_populate_animations_list()
		return
	_current_weapon.animation_library = library

	_populate_animations_list()

	# Update animation names, should only be called when opening old files or renaming weapon resource_name
	_current_weapon.fix_move_animation_names_list()

	if is_instance_valid(_weapon_handler):
		_weapon_handler.load_weapon_information(_current_weapon)

func _populate_animations_list() -> void:
	if !_current_weapon:
		return

	var selected: int = animation_button.selected
	var anim_list: PackedStringArray = _current_weapon.get_animation_list()

	# Use the animations in the character's AnimationMixer
	if anim_list.is_empty():
		if not is_instance_valid(_weapon_handler):
			return
		anim_list = _weapon_handler.animation_tree.get_animation_list()

	animation_button.clear()
	for animation: String in anim_list:
		animation_button.add_item(animation)
	animation_button.select(selected)
#endregion


#region Animation Viewer
## Stores position and velocity
var saved_states: Dictionary[int, CharacterReplayState] = {}

func _reset_saved_states() -> void:
	if _simulating_move:
		return
	saved_states.clear()

func _on_start_button_pressed():
	if !_current_move || !_current_weapon || !_weapon_handler:
		return

	if is_instance_valid(_character_scene):
		_on_reset_character_position_pressed()

	_update_handler_state()

	_simulating_move = false
	_weapon_handler.start_move(_current_move)


func _on_continue_button_pressed():
	if !_current_move || !_current_weapon || !_weapon_handler:
		return

	_simulating_move = false
	_weapon_handler.real_frame = frame_box.value
	_weapon_handler.continue_move()


func _on_pause_button_pressed():
	if !_current_move || !_current_weapon || !_weapon_handler:
		return

	_simulating_move = false
	_weapon_handler.pause_move()
	if is_instance_valid(_weapon_handler.animation_tree):
		_weapon_handler.animation_tree.process_mode = Node.PROCESS_MODE_ALWAYS


func _on_weapon_handler_frame_processed() -> void:
	if _simulating_move:
		return
	if _weapon_handler.frame < 0:
		return
	_sync_frame_ui(_weapon_handler.frame)
	_update_handler_state()
	saved_states[_weapon_handler.frame] = CharacterReplayState.new(_character_scene, _weapon_handler)
	if _character_scene is CharacterBody3D:
		_character_scene.velocity = _weapon_handler.velocity
		_character_scene.move_and_slide()


func _on_weapon_handler_move_started(move: WeaponMove) -> void:
	if is_instance_valid(_weapon_handler.animation_tree):
		_weapon_handler.animation_tree.set(
			&"parameters/Transition/transition_request",
			"attack"
		)
	_reset_saved_states()
	if _character_scene.get_meta(&"reset_on_new_move", false):
		_on_reset_character_position_pressed()
		_character_scene.remove_meta(&"reset_on_new_move")
	_character_scene.remove_meta(&"grab_ended")

	if is_instance_valid(move_tree):
		var items_queue: Array[TreeItem] = [move_tree.get_root()]
		while not items_queue.is_empty():
			var item: TreeItem = items_queue.pop_front()
			var item_move: WeaponMove = item.get_metadata(0) as WeaponMove
			if move != _current_move and is_instance_valid(item_move) and item_move == move:
				for i: int in range(move_tree.columns):
					item.set_custom_bg_color(i, _color_highlight)
			else:
				for i: int in range(move_tree.columns):
					if item.has_meta(&"bg_color"):
						item.set_custom_bg_color(i, item.get_meta(&"bg_color"))
					else:
						item.clear_custom_bg_color(i)
			if not item.collapsed:
				items_queue.append_array(item.get_children())


func _on_weapon_handler_move_stopped() -> void:
	_character_scene.velocity = Vector3.ZERO
	# Combo string ended or move is just done
	if not _weapon_handler.get_current_move():
		_character_scene.set_meta(&"reset_on_new_move", true)

	var items_queue: Array[TreeItem] = [move_tree.get_root()]
	while not items_queue.is_empty():
		var item: TreeItem = items_queue.pop_front()
		for i: int in range(move_tree.columns):
			if item.has_meta(&"bg_color"):
				item.set_custom_bg_color(i, item.get_meta(&"bg_color"))
			else:
				item.clear_custom_bg_color(i)
		items_queue.append_array(item.get_children())


func refresh_animation() -> void:
	_weapon_handler.frame = _weapon_handler.frame
	scene_container.queue_redraw()


func _sync_frame_ui(value: int) -> void:
	frame_box.set_value_no_signal(value)
	scene_container.queue_redraw()


func _seek_frame(value: int) -> void:
	if value < 0 || not is_instance_valid(_weapon_handler):
		return

	if not _weapon_handler.get_current_move() and _current_move:
		_simulate_new_move(value)
		if saved_states.has(value):
			saved_states[value].apply(_character_scene, _weapon_handler)
		return

	_sync_frame_ui(value)

	var current_frame: int = _weapon_handler.frame
	if current_frame == value:
		return

	# Move changed somewhere
	if _weapon_handler.get_current_move() != _current_move:
		return

	# seek backwards.
	if value < current_frame:
		if saved_states.has(value):
			saved_states[value].apply(_character_scene, _weapon_handler)
			_weapon_handler.frame = value
			_weapon_handler.seek_frames(value)
			_weapon_handler.process_frame()
	# seek forward.
	elif value > current_frame:
		while current_frame < value:
			current_frame += 1
			_weapon_handler.frame = current_frame
			_weapon_handler.process_frame()
			# Move stopped
			if _weapon_handler.get_current_move() != _current_move:
				return


func _simulate_new_move(to_frame: int, lock_move: bool = true, no_states: bool = true) -> void:
	_simulating_move = no_states
	set_deferred(&"_simulating_move", false)
	_weapon_handler.start_move(_current_move)

	if to_frame == 0:
		_reset_saved_states()
		return
	# Simulate from nothing to current state
	var seeking_move: WeaponMove = _current_move
	var offset: int = 0
	for i: int in range(to_frame + 1):
		_weapon_handler.frame = i - offset
		_weapon_handler.set_meta(&"lock_move", lock_move)
		_weapon_handler.process_frame()
		# Simulation ended
		if not _weapon_handler.get_current_move():
			if not saved_states.is_empty():
				saved_states[saved_states.keys().max()].apply(_character_scene, _weapon_handler)
			return
		# Simulation transitioned to new move
		elif _weapon_handler.get_current_move() != seeking_move:
			seeking_move = _weapon_handler.get_current_move()
			_weapon_handler.pause_move()
			offset = maxi(i + 1, 0)
			return


func _update_frame_time_limit() -> void:
	if !_current_anim || !_current_move:
		return
	if !_current_anim.has_animation(_current_move.animation):
		return
	frame_box.max_value = roundi(_current_anim.get_animation(_current_move.animation).length * Engine.physics_ticks_per_second)


func simulate_then_seek(to_frame: int) -> void:
	if not _current_move:
		return
	saved_states.clear()
	_on_reset_character_position_pressed()
	_simulate_new_move(200, false, false)
	_weapon_handler.start_move(_current_move)
	_weapon_handler.pause_move()
	_seek_frame(to_frame)
#endregion


#region Move Buttons
func _on_move_remove_dialog_confirmed():
	if !_current_move:
		return

	var selected: TreeItem = move_tree.get_selected()
	var parent: TreeItem = selected.get_parent()
	parent.remove_child(selected)

	move_tree.deselect_all()

	if parent == move_tree.get_root():
		_current_weapon.moves.erase(_current_move)
	else:
		var parent_move: WeaponMove = parent.get_metadata(0) as WeaponMove
		parent_move.next_moves.erase(_current_move)

	update_move_tree.call_deferred()
	_current_move = null


func _on_move_add_pressed():
	if !_current_weapon:
		return

	if _current_weapon.moves.is_empty():
		_current_weapon.moves = [WeaponMove.new()]
	else:
		_current_weapon.moves.append(WeaponMove.new())
	update_move_tree.call_deferred()


func _on_move_add_child_pressed():
	if !_current_move:
		return

	if _current_move.next_moves.is_empty():
		_current_move.next_moves = [WeaponMove.new()]
	else:
		_current_move.next_moves.append(WeaponMove.new())
	update_move_tree.call_deferred()


func _on_move_up_pressed():
	var selected: TreeItem = move_tree.get_selected()
	if !selected.get_prev():
		return
	selected.move_before(selected.get_prev())

	var array: Array = _get_current_moves_array()

	var index: int = array.find(selected.get_metadata(0))
	var new_index = maxi(index - 1, 0)

	array[index] = array[new_index]
	array[new_index] = selected.get_metadata(0)


func _on_move_down_pressed():
	var selected: TreeItem = move_tree.get_selected()
	if !selected.get_next():
		return
	move_tree.get_selected().move_after(selected.get_next())

	var array: Array = _get_current_moves_array()

	var index: int = array.find(selected.get_metadata(0))
	var new_index = mini(index + 1, array.size()-1)

	array[index] = array[new_index]
	array[new_index] = selected.get_metadata(0)


func _on_move_linked_child_pressed() -> void:
	if not _current_weapon:
		return
	var popup: PopupPanel = get_meta(&"linked_popup", PopupPanel.new()) as PopupPanel
	if not has_meta(&"linked_popup"):
		set_meta(&"linked_popup", popup)
		var tree: Tree = Tree.new()
		popup.add_child(tree)
		tree.item_activated.connect(_on_link_tree_item_activated.bind(tree))
		add_child(popup)

	var link_tree: Tree = popup.get_child(0) as Tree
	link_tree.clear()
	var root: TreeItem = link_tree.create_item()
	link_tree.hide_root = true

	for move: WeaponMove in _current_weapon.moves:
		_add_link_tree_moves(move, root, link_tree)

	popup.popup_centered(Vector2i.ONE * 512)


func _add_link_tree_moves(weapon_move: WeaponMove, parent_tree_item: TreeItem = null, tree: Tree = move_tree) -> void:
	var new_move_item: TreeItem = tree.create_item(parent_tree_item)
	if weapon_move == _current_move:
		new_move_item.set_custom_color(0, Color.RED)
	new_move_item.set_metadata(0, weapon_move)
	new_move_item.set_text(0, weapon_move.name)

	for next_move: WeaponMove in weapon_move.next_moves:
		_add_link_tree_moves(next_move, new_move_item, tree)


func _on_link_tree_item_activated(link_tree: Tree) -> void:
	var selected_move: WeaponMove = link_tree.get_selected().get_metadata(0) as WeaponMove
	if move_tree.get_selected() and _current_move:
		if selected_move == _current_move:
			return
		_current_move.next_moves.append(selected_move)
	else:
		if _current_weapon.moves.has(selected_move):
			return
		_current_weapon.moves.append(selected_move)
	update_move_tree()
	link_tree.get_parent().hide()


func _update_tree_linked_count() -> void:
	var item: TreeItem = move_tree.get_root()

	while item != null:
		item = item.get_next_in_tree()
		if item == null:
			continue
		var weapon_move: WeaponMove = item.get_metadata(0)

		if _added_moves.count(weapon_move) > 1:
			item.set_custom_font(move_tree.columns - 1, get_theme_font(&"font", &"HeaderSmall"))
			item.set_text(move_tree.columns - 1, "%d" % _added_moves.count(weapon_move))
			item.set_text_overrun_behavior(move_tree.columns - 1, TextServer.OVERRUN_NO_TRIMMING)
			item.set_icon(move_tree.columns - 1, _icon_linked)


func _get_current_moves_array() -> Array:
	var selected: TreeItem = move_tree.get_selected()
	if !selected:
		return []
	return _current_weapon.moves if selected.get_parent() == move_tree.get_root() else selected.get_parent().get_metadata(0).next_moves


func _on_move_refresh_pressed():
	update_move_tree()


func _on_move_preview_pressed() -> void:
	if not _current_weapon:
		return
	%MovePreviewText.text = WeaponMovesLabel.get_weapon_moves_rich_text(_current_weapon)
	%MovePreviewDialog.popup_centered()
#endregion

func _on_scene_container_draw() -> void:
	var bone_index: int = get_meta(&"selected_bone", -1)
	if bone_index < 0:
		return

	var cam := %Camera3D
	var skeleton_transform := _weapon_handler.skeleton.get_global_transform()

	var bones_queue: Array[int] = []
	bones_queue.assign(_weapon_handler.skeleton.get_parentless_bones())
	while not bones_queue.is_empty():
		var i: int = bones_queue.pop_front()
		var origin_transform := _weapon_handler.skeleton.get_bone_global_pose(i)
		var origin_pos: Vector2 = cam.unproject_position(
			(skeleton_transform * origin_transform).origin
		)
		var color := Color.DIM_GRAY
		var string: String = ""
		if i == bone_index:
			color = Color.ORANGE_RED
			scene_container.draw_circle(
				origin_pos,
				4.0,
				color
			)
			string = _weapon_handler.skeleton.get_bone_name(i)

		var children: PackedInt32Array = _weapon_handler.skeleton.get_bone_children(i)
		if children.is_empty():
			var child_transform := origin_transform.translated_local(Vector3.UP * 0.2)
			scene_container.draw_line(
				origin_pos,
				cam.unproject_position((skeleton_transform * child_transform).origin),
				color
			)
		else:
			for j: int in children:
				bones_queue.append(j)
				var child_transform := _weapon_handler.skeleton.get_bone_global_pose(j)
				scene_container.draw_line(
					origin_pos,
					cam.unproject_position((skeleton_transform * child_transform).origin),
					color
				)
		if not string.is_empty():
			scene_container.draw_string_outline(
				get_theme_default_font(),
				origin_pos,
				string,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				get_theme_default_font_size(),
				8,
				Color.BLACK
			)
			scene_container.draw_string(
				get_theme_default_font(),
				origin_pos,
				string,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				get_theme_default_font_size()
			)

#region Weapon
func _on_weapon_name_edit_text_changed(new_text):
	if !_current_weapon:
		return

	_current_weapon.name = new_text


func _icon_file_selected(path: String) -> void:
	if !_current_weapon:
		return

	%IconEdit.text = path
	_current_weapon.icon = load(path)
	%IconPreview.texture = _current_weapon.icon


func _save_weapon() -> void:
	ResourceSaver.save(_current_weapon)
#endregion

#region Character State Handling
@onready var state_grounded: OptionButton = %StateGrounded
@onready var state_ground_height := EditorSpinSlider.new()
@onready var state_lock_x: BaseButton = %StateLockX
@onready var state_lock_y: BaseButton = %StateLockY
@onready var state_lock_z: BaseButton = %StateLockZ
@onready var state_label: Label = %StateLabel
@onready var state_no_transition: CheckBox = %StateNoTransition

func _update_handler_state() -> void:
	var character_y: float = _character_scene.global_position.y
	var ground_y: float = state_ground_height.value
	var new_grounded: bool = false

	match state_grounded.selected:
		0: # Auto
			new_grounded = (character_y - 0.01) <= ground_y || is_equal_approx(character_y, ground_y)
		1: # False, InAir
			new_grounded = false
		2: # True, Grounded
			new_grounded = true

	if new_grounded:
		_character_scene.global_position.y = maxf(character_y, ground_y)

	state_label.text = ("Grounded" if new_grounded else "In Air")
	#_character_scene._grounded = new_grounded

	if state_lock_x.is_pressed():
		_character_scene.position.x = 0.0
		_character_scene.velocity.x = 0.0

	if state_lock_y.is_pressed():
		_character_scene.position.y = ground_y
		_character_scene.velocity.y = 0.0

	if state_lock_z.is_pressed():
		_character_scene.position.z = 0.0
		_character_scene.velocity.z = 0.0

	if is_instance_valid(_weapon_handler):
		_weapon_handler.set_meta(&"lock_move", state_no_transition.is_pressed())

		for i: int in range(_state_handler_hit_toggles.size()):
			var btn: Button = _state_handler_hit_toggles[i]
			var toggled_on: bool = btn.is_pressed() and not btn.is_disabled()

			match i:
				0:
					_weapon_handler.hit_landed = toggled_on


func _on_reset_character_position_pressed() -> void:
	if not is_instance_valid(_character_scene):
		return
	_character_scene.position = Vector3.UP * state_ground_height.value
	_character_scene.rotation = Vector3.ZERO
	_character_scene.velocity = Vector3.ZERO
	_character_scene.move_and_collide(Vector3.DOWN)

#endregion

func _quick_shortcut(key: Key, shift: bool = false, alt: bool = false) -> Shortcut:
	var shortcut := Shortcut.new()
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	key_event.pressed = true
	key_event.shift_pressed = shift
	key_event.alt_pressed = alt
	shortcut.events = [key_event]
	return shortcut


func _on_tree_node_added(node: Node) -> void:
	if not _simulating_move:
		return
	if not is_instance_valid(_character_scene):
		return
	if not _character_scene.is_ancestor_of(node):
		return
	if node.get_meta(&"_debug_hidden", false):
		return
	node.queue_free()


class CharacterReplayState extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var gravity: float = -1.0
	var drag: float = -1.0
	var cancel_flags: int = 0

	func _init(character: CharacterBody3D = null, handler: WeaponHandler = null) -> void:
		if not is_instance_valid(character):
			return
		position = character.global_position
		rotation = character.global_rotation
		velocity = character.velocity

		if is_instance_valid(handler):
			cancel_flags = handler._cancel_flags

	func apply(character: CharacterBody3D, handler: WeaponHandler) -> void:
		character.global_position = position
		character.global_rotation = rotation
		character.velocity = velocity
		if is_instance_valid(handler):
			handler._cancel_flags = cancel_flags
