@tool
extends PanelContainer

signal update_tree_requested

var move: WeaponMove:
	set = edit_move

@onready var name_edit: LineEdit = %NameEdit
# Activation
@onready var input_option: OptionButton = %InputOption
@onready var conditions_box: Control = %ConditionsBox
# Damage
@onready var damage_tab_container: TabContainer = %DamageTabContainer
# Visual
@onready var visual_hold_button: CheckBox = %VisualHoldButton
@onready var visual_exclude_button: CheckBox = %VisualExcludeButton
@onready var visual_exclude_if_child_button: CheckBox = %VisualExcludeIfChildButton
@onready var visual_attributes_up_button: CheckBox = %VisualAttributesUpButton
@onready var visual_exclude_if_root_button: CheckBox = %VisualExcludeIfRootButton
@onready var visual_input_option: OptionButton = %VisualInputOption
# Behavior
@onready var behaviour_no_turn_button: CheckBox = %BehaviourNoTurnButton

func setup() -> void:
	var edit_script_button: Button = %EditMoveScript
	if EditorInterface.has_user_signal(&"edit_move_script"):
		edit_script_button.pressed.connect(
			func() -> void:
				if not move:
					return
				EditorInterface.emit_signal(&"edit_move_script", move)
				EditorInterface.set_main_screen_editor("Script")
		)
	else:
		edit_script_button.hide()

	%InspectMove.pressed.connect(
		func() -> void:
			if not move:
				return
			EditorInterface.inspect_object(move, "", true)
	)

	_populate_conditions()

	name_edit.text_changed.connect(_set_move_property.bind(&"name"))

	# Connect button signals
	input_option.item_selected.connect(
		func(index: int) -> void:
			_set_move_property(index - 1, &"input")
	)

	visual_hold_button.toggled.connect(_set_move_property.bind(&"visual_hold"))
	visual_exclude_if_child_button.toggled.connect(
		_set_move_property.bind(&"visual_exclude_if_child"),
	)
	visual_attributes_up_button.toggled.connect(
		_set_move_property.bind(&"propagate_attributes_up"),
	)
	visual_exclude_if_root_button.toggled.connect(func(toggled_on: bool) -> void:
		var flags_value: int = move.visual_flags if move else 0
		if toggled_on:
			flags_value = flags_value | WeaponMove.VisualFlag.EXCLUDE_IF_ROOT
		else:
			flags_value = flags_value & ~WeaponMove.VisualFlag.EXCLUDE_IF_ROOT
		_set_move_property(flags_value, &"visual_flags")
	)
	visual_input_option.item_selected.connect(
		func(index: int) -> void:
			_set_move_property(index - 1, &"visual_input")
	)

	# Setup damage tabs
	var damage_tab_popup := PopupMenu.new()
	damage_tab_popup.add_icon_item(
		get_theme_icon(&"Add", &"EditorIcons"),
		"Create New Damage",
		0,
	)
	damage_tab_popup.add_item("Create New Probe Damage", 2)
	damage_tab_popup.add_separator("", 1000)
	damage_tab_popup.add_icon_item(
		get_theme_icon(&"Remove", &"EditorIcons"),
		"Delete Selected",
		1,
	)
	add_child(damage_tab_popup)
	damage_tab_container.set_popup(damage_tab_popup)
	damage_tab_popup.id_pressed.connect(
		_on_damage_editors_popup_id_selected,
	)


func edit_move(value: WeaponMove) -> void:
	move = value
	visible = is_instance_valid(move)

	_update_damage_editors()

	sync_all()


func set_extra_input_count(count: int) -> void:
	# Remove previously added extra attack inputs
	input_option.set_item_count(3)

	# Add extra attack inputs based on character
	for i: int in range(count):
		input_option.add_item("Extra %s" % (i + 1))


func sync_all() -> void:
	if not move:
		return

	var caret_position: int = name_edit.caret_column
	name_edit.text = move.name
	name_edit.caret_column = caret_position

	input_option.select(move.input + 1)
	_sync_condition_buttons()

	visual_hold_button.set_pressed_no_signal(move.visual_hold)
	visual_exclude_if_child_button.set_pressed_no_signal(move.visual_exclude_if_child)
	visual_attributes_up_button.set_pressed_no_signal(
		move.propagate_attributes_up,
	)
	visual_exclude_if_root_button.set_pressed_no_signal(
		move.visual_flags & WeaponMove.VisualFlag.EXCLUDE_IF_ROOT
	)
	visual_input_option.select(move.visual_input + 1)


func _populate_conditions() -> void:
	for i: int in range(1, WeaponMove.Condition.size()):
		var b: CheckBox = CheckBox.new()
		b.text = WeaponMove.Condition.keys()[i]
		b.text = b.text.capitalize()

		conditions_box.add_child(b)
		b.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		b.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		b.pressed.connect(_on_condition_button_pressed.bind(b, i - 1))
	conditions_box.queue_redraw()


func _sync_condition_buttons() -> void:
	for i: int in range(conditions_box.get_child_count()):
		var b: BaseButton = conditions_box.get_child(i) as BaseButton
		b.set_pressed_no_signal(move.conditions & (1 << i))

	_update_state()


func _on_condition_button_pressed(button: BaseButton, flag_bit: int) -> void:
	if not move:
		return

	var new_value: int = move.conditions
	if button.button_pressed:
		new_value |= (1 << flag_bit)
	else:
		new_value &= ~(1 << flag_bit)

	_set_move_property(new_value, &"conditions")


func _set_move_property(value: Variant, property: StringName) -> void:
	if not move:
		return

	var original_value: Variant = move.get(property)
	if value == original_value:
		return

	var undoredo := EditorInterface.get_editor_undo_redo()
	var merge := UndoRedo.MERGE_DISABLE
	if typeof(value) == TYPE_STRING:
		merge = UndoRedo.MERGE_ENDS

	undoredo.create_action("Set Move's %s" % property, merge)
	undoredo.add_do_property(move, property, value)
	undoredo.add_undo_property(move, property, original_value)
	undoredo.add_do_method(self, &"sync_all")
	undoredo.add_undo_method(self, &"sync_all")
	undoredo.add_do_method(EditorInterface, &"set_object_edited", move, true)
	undoredo.add_undo_method(EditorInterface, &"set_object_edited", move, true)
	undoredo.commit_action()

	_update_state()


func _update_damage_editors() -> void:
	for child: Node in damage_tab_container.get_children():
		child.queue_free()
		damage_tab_container.remove_child(child)

	if not move:
		return

	if move.damage.is_empty():
		var empty := Label.new()
		empty.name = "[empty]"
		damage_tab_container.add_child(empty)
		return

	for i: int in range(move.damage.size()):
		var inspector := EditorInspector.new()
		inspector.name = var_to_str(i)
		inspector.edit(move.damage[i])
		damage_tab_container.add_child(inspector)


func _on_damage_editors_popup_id_selected(id: int) -> void:
	if not move:
		return

	match id:
		0:
			move.damage.append(WeaponDamage.new())
		1:
			if not move.damage.is_empty():
				move.damage.remove_at(damage_tab_container.current_tab)
		2:
			move.damage.append(WeaponDamage.new_probe())

	_update_damage_editors()


func _update_state() -> void:
	update_tree_requested.emit()
