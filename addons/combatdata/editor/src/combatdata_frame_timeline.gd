@tool
extends Slider

const FLAG_HIT_ACTIVE: int = 1 << 8
const FLAG_HIT_GRAB: int = 1 << 9
const FLAG_HIT_PROBE: int = 1 << 10
const FLAG_HIT_MULTI: int = 1 << 11
const FLAG_HIT_REARM: int = 1 << 12

const ALL_CUSTOM_FLAGS: int = (
	FLAG_HIT_ACTIVE \
	| FLAG_HIT_GRAB \
	| FLAG_HIT_PROBE \
	| FLAG_HIT_MULTI \
	| FLAG_HIT_REARM \
)

var weapon_handler: WeaponHandler:
	set = set_weapon_handler
var end_frame: int = -1:
	set(value):
		end_frame = value
		queue_redraw()

var _dragging: bool = false
var _flags_history := PackedInt32Array()
var _tooltip_panel := PanelContainer.new()
var _tooltip_label := Label.new()
var _last_move: WeaponMove = null
var _move_transition_history: Dictionary[int, WeaponMove] = {}
var _frames_offset: int = 0
var _move_transitioned: bool = false
# Colors
var _color_base := Color.BLACK
var _color_border := Color.BLACK
var _color_mono := Color.BLACK
var _color_mono_invert := Color.BLACK
var _color_flag_light := Color.BLACK
var _color_flag_heavy := Color.BLACK
var _color_flag_jump := Color.BLACK
var _color_flag_dash := Color.BLACK

func _ready() -> void:
	_tooltip_panel.hide()
	_tooltip_panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_tooltip_panel.theme_type_variation = &"TooltipPanel"
	_tooltip_panel.z_index = 10
	mouse_exited.connect(_tooltip_panel.hide)
	_tooltip_label.theme_type_variation = &"TooltipLabel"
	_tooltip_panel.add_child(_tooltip_label)
	add_child(_tooltip_panel)


func _draw() -> void:
	var frame_count: int = _get_final_frame()
	var frame_width: float = size.x / frame_count
	var rect := Rect2(Vector2.ZERO, Vector2(frame_width, size.y))
	var radius: float = rect.size[rect.size.min_axis_index()] * 0.15
	var unprocessed_color: Color = Color.RED.lerp(_color_mono, 0.5)
	var current_frame: int = roundi(value) + _frames_offset
	unprocessed_color.a = 0.2
	for i: int in range(frame_count):
		_draw_cancel_flag_rect(rect, _get_flags_at(i))
		if i == current_frame:
			draw_circle(rect.get_center(), radius + 1.0, _color_mono_invert, true, -1.0, true)
			draw_circle(rect.get_center(), radius, _color_mono, true, -1.0, true)
		draw_rect(rect, _color_border, false, 2)
		if i >= end_frame:
			draw_rect(rect, unprocessed_color)
		elif i > 0 and _move_transition_history.keys().has(i):
			draw_line(rect.position, Vector2(rect.position.x, rect.end.y), _color_mono, 2.0, true)
		rect.position.x += frame_width


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_color_base = get_theme_color(&"base_color", &"Editor")
		_color_border = get_theme_color(&"dark_color_1", &"Editor")
		_color_mono = get_theme_color(&"mono_color", &"Editor")
		_color_mono_invert = _color_mono.inverted()

		_color_flag_light = Color.DEEP_SKY_BLUE.lerp(_color_mono, 0.2)
		_color_flag_heavy = Color.DARK_ORANGE.lerp(_color_mono_invert, 0.2)
		_color_flag_jump = Color.MEDIUM_VIOLET_RED.lerp(_color_mono, 0.2)
		_color_flag_dash = Color.DARK_GREEN.lerp(_color_mono, 0.1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		var new_value: int = floori((event.position.x / size.x) * _get_final_frame())
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_dragging = event.is_pressed()
				_set_value_frame(new_value)
				accept_event()
		elif event is InputEventMouseMotion:
			if _dragging:
				_set_value_frame(new_value)
				accept_event()
				_tooltip_panel.visible = false
			else:
				var pos: Vector2 = event.position
				pos += Vector2.ONE * 12.0
				_tooltip_panel.position = pos
				_tooltip_label.text = "Frame %d\n%s" % [new_value, _get_cancel_text_at(new_value)]
				_tooltip_panel.visible = true
				_tooltip_panel.reset_size.call_deferred()


func setup() -> void:
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override(&"grabber_area", empty)
	add_theme_stylebox_override(&"grabber_area_highlight", empty)
	add_theme_stylebox_override(&"slider", empty)
	var empty_img := ImageTexture.new()
	add_theme_icon_override(&"grabber", empty_img)
	add_theme_icon_override(&"grabber_highlight", empty_img)
	add_theme_icon_override(&"grabber_disabled", empty_img)
	add_theme_icon_override(&"tick", empty_img)

	custom_minimum_size.y = 38.0
	rounded = true

	_flags_history = []
	changed.connect(func() -> void:
		_flags_history.resize(ceili(max_value) + 1)
		_flags_history.fill(0)
	)


func clear_all() -> void:
	end_frame = -1
	clear_transitions()


func clear_transitions(reset_offset: bool = true) -> void:
	_move_transitioned = false
	_move_transition_history.clear()
	if reset_offset:
		_last_move = null
		_frames_offset = 0


func set_weapon_handler(new_handler: WeaponHandler) -> void:
	if new_handler == weapon_handler:
		return
	if is_instance_valid(weapon_handler):
		weapon_handler.move_started.disconnect(_on_move_started)
		weapon_handler.frame_processed.disconnect(_on_frame_processed)
	weapon_handler = new_handler
	if is_instance_valid(weapon_handler):
		weapon_handler.move_started.connect(_on_move_started)
		weapon_handler.move_stopped.connect(_on_move_stopped)
		weapon_handler.frame_processed.connect(_on_frame_processed)


func _set_value_frame(frame: int) -> void:
	frame = mini(frame, end_frame - 1)
	value = frame


func _get_final_frame() -> int:
	return mini(
		maxi(
			maxi(ceili(max_value) + 1, _flags_history.size()),
			end_frame + 1
		),
		200
	)


func _draw_cancel_flag_rect(rect: Rect2, flags: int) -> void:
	if flags == 0:
		return

	var under_color := Color.TRANSPARENT
	var active_hitbox: bool = _is_flag(flags, FLAG_HIT_ACTIVE)
	var rearm: bool = _is_flag(flags, FLAG_HIT_REARM)
	if active_hitbox:
		under_color = Color.RED
	if _is_flag(flags, FLAG_HIT_PROBE):
		under_color = Color.CYAN
	if _is_flag(flags, FLAG_HIT_GRAB):
		under_color = Color.GREEN if active_hitbox else Color.GRAY
	if rearm:
		if under_color.a < 0.5:
			under_color = _color_base
	if under_color.a > 0.5:
		var under_rect: Rect2 = rect.grow_side(SIDE_TOP, -rect.size.y * 0.8)
		draw_rect(under_rect, under_color.lerp(_color_mono, 0.1))
		rect.size.y -= under_rect.size.y
		if rearm:
			draw_rect(under_rect.grow_side(SIDE_RIGHT, -under_rect.size.x * 0.6), _color_mono)
		draw_line(Vector2(rect.position.x, rect.end.y), rect.end, _color_base, 2)

	var rect_l := rect
	var rect_h := rect
	var center: Vector2 = rect.get_center()
	var diag_length: float = minf(rect.size.x * 0.7, rect.size.y * 0.5)

	var is_light: bool = flags & WeaponHandler.Cancel.LIGHT
	var is_heavy: bool = flags & WeaponHandler.Cancel.HEAVY
	if is_light and _is_flag(flags, WeaponHandler.Cancel.END_LIGHT):
		rect_l = rect.grow_side(SIDE_RIGHT, -rect.size.x * 0.4)
	if is_heavy and _is_flag(flags, WeaponHandler.Cancel.END_HEAVY):
		rect_h = rect.grow_side(SIDE_RIGHT, -rect.size.x * 0.4)

	if _is_flag(flags, WeaponHandler.Cancel.END):
		is_light = false
		is_heavy = false
		draw_rect(rect, _color_mono.lerp(_color_base, 0.2))

	if is_light:
		if is_heavy:
			rect_l = rect_l.grow_side(SIDE_BOTTOM, -rect_l.size.y * 0.5)
		draw_rect(rect_l, _color_flag_light.lerp(_color_mono_invert, 0.2))
		draw_rect(rect_l.grow_individual(0.0, -rect_l.size.y * 0.75, 0.0, 0.0), _color_flag_light)
		draw_rect(
			rect_l.grow_individual(0.0, -rect_l.size.y * 0.25, 0.0, -rect_l.size.y * 0.5),
			_color_flag_light
		)

	if is_heavy:
		if is_light:
			rect_h = rect_h.grow_side(SIDE_TOP, -rect_h.size.y * 0.5)
		draw_rect(rect_h, _color_flag_heavy.lerp(_color_mono, 0.3))
		draw_rect(
			rect_h.grow_individual(-rect_h.size.x * 0.5, 0.0, -rect_h.size.x * 0.25, 0.0),
			_color_flag_heavy
		)
		draw_rect(
			rect_h.grow_individual(0.0, 0.0, -rect_h.size.x * 0.75, 0.0),
			_color_flag_heavy
		)

	if flags & WeaponHandler.Cancel.JUMP:
		var points := PackedVector2Array([
			rect.position,
			Vector2(rect.position.x + diag_length, rect.position.y),
			Vector2(rect.position.x, rect.position.y + diag_length)
		])
		draw_colored_polygon(points, _color_flag_jump)
		draw_line(points[1], points[2], _color_base, 0.6, true)

	if flags & WeaponHandler.Cancel.DASH:
		var points := PackedVector2Array([
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x + diag_length, rect.end.y),
			Vector2(rect.position.x, rect.end.y - diag_length)
		])
		draw_colored_polygon(points, _color_flag_dash)
		draw_line(points[1], points[2], _color_base, 0.6, true)


func _on_move_started(move: WeaponMove) -> void:
	weapon_handler.remove_meta(&"rearmed")
	if move == _last_move:
		return
	if not _move_transitioned:
		_flags_history.fill(0)
		clear_transitions()
		end_frame = -1
		_frames_offset = 0
	else:
		_frames_offset = maxi(end_frame, 0)
	_last_move = move
	_move_transition_history[_frames_offset] = move


func _on_move_stopped() -> void:
	end_frame = maxi(end_frame, weapon_handler.frame)
	# Move transitioned to another one
	var cm := weapon_handler.get_current_move()
	if is_instance_valid(cm) and not _move_transition_history.values().has(cm):
		_move_transitioned = true
	else:
		# Queue clearing transition to next move
		_move_transitioned = false
		_flags_history.resize(end_frame + 1)


func _on_frame_processed() -> void:
	var history_frame: int = weapon_handler.frame + _frames_offset
	_flags_history.resize(maxi(_flags_history.size(), history_frame + 1))
	if weapon_handler.frame < 0:
		return
	end_frame = maxi(end_frame, history_frame + 1)

	var flags: int = weapon_handler._cancel_flags

	if weapon_handler.get_meta(&"rearmed", -1) == weapon_handler.frame:
		flags = flags | FLAG_HIT_REARM

	var hit_count: int = 0
	for hit_area: WeaponHitArea in weapon_handler.hit_areas:
		if not hit_area.is_disabled(weapon_handler.frame):
			hit_count += 1
			if hit_count > 1:
				flags = flags | FLAG_HIT_MULTI
			flags = flags | FLAG_HIT_ACTIVE
			if hit_area.is_probe():
				flags = flags | FLAG_HIT_PROBE

	_flags_history[history_frame] = flags


func _get_flags_at(frame: int) -> int:
	if frame >= _flags_history.size():
		return 0
	return _flags_history[frame]


func _get_cancel_text_at(frame: int) -> String:
	if frame >= end_frame:
		return "End"
	var flags: int = _get_flags_at(frame)

	var flag_strings := PackedStringArray()
	var out: String = ""

	# Remove all custom flags
	flags &= ~ALL_CUSTOM_FLAGS

	if flags == 0:
		flag_strings.append("No Cancels")
	else:
		for key: StringName in WeaponHandler.Cancel:
			var cancel_value: int = WeaponHandler.Cancel.get(key)
			if cancel_value == 0 or cancel_value == WeaponHandler.Cancel.ANY_ATTACK:
				continue
			if _is_flag(flags, cancel_value):
				flag_strings.append(key.capitalize())

	out = "%s\n(0b%s)" % [", ".join(flag_strings), String.num_uint64(flags, 2).pad_zeros(6)]

	if not _move_transition_history.is_empty() and _move_transition_history.has(0):
		var current_move: WeaponMove = _move_transition_history[0]
		for transition_frame: int in _move_transition_history.keys():
			if transition_frame <= frame:
				current_move = _move_transition_history[transition_frame]
		out = "Move: %s\n%s" % [current_move.name, out]

	return out


func _is_flag(flags: int, target: int) -> bool:
	return (flags & target) == target
