@tool
extends PanelContainer

const FrameTimeline := preload("./combatdata_frame_timeline.gd")

const TRACK_HEIGHT: float = 40.0
const TIME_MARKER_POINTER_WIDTH: float = 6.0
const TIME_MARKER_LINE_WIDTH: float = 3.0
const TIMELINE_OFFSET_FRAMES: int = -1

@export var frame_timeline: FrameTimeline

var handler: WeaponHandler:
	set(value):
		# Disconnect previous handler
		if is_instance_valid(handler):
			handler.frame_processed.disconnect(_on_frame_processed)

		handler = value
		if is_instance_valid(handler) and is_instance_valid(timeline):
			handler.frame_processed.connect(_on_frame_processed)

var move: WeaponMove:
	set(value):
		move = value
		if move and handler and is_instance_valid(h_scroll_bar):
			if handler.animation_tree.has_animation(move.animation):
				var anim := handler.animation_tree.get_animation(move.animation)
				_animation_length = anim.length
			else:
				_animation_length = 1.0
		update_timeline.call_deferred()
		if is_instance_valid(_track_sections):
			_track_sections.queue_redraw()

var _font: Font
var _font_size: float
var _time_marker_dragger:= Rect2(Vector2.ZERO, Vector2.ONE)
var _timeline_bg_color: Color
var _timeline_end_time: float = 1.0
var _seeking: bool = false
# Stores Class name as key and Script path as value
# e.g. ["WeaponTrackCustom": "res://path_to_script.gd"]
var _tracks_classes: Dictionary[String, String] = {}
var _shade_texture: Texture2D
var _shade_color: Color
var _tracks_rects: Array[Rect2] = []
var _hovered_rect: int = -1:
	set(value):
		if _hovered_rect == value:
			return
		_hovered_rect = value
		if is_instance_valid(tracks_view):
			tracks_view.queue_redraw()
var _pixels_per_frame: float = 0.0
var _use_seconds: bool = false
var _time_ruler_height: float = 0.0
var _timeline_marker_bg_stylebox := StyleBoxFlat.new()
var _setup_complete: bool = false
var _animation_length: float = 0.0
# Track sections
var _track_sections: Control
var _track_sections_clip: Control
var _track_section_stylebox := StyleBoxFlat.new()
var _track_section_rects: Array[Rect2] = []
var _track_section_hover_index: int = -1:
	set(value):
		if _track_section_hover_index == value:
			return
		_track_section_hover_index = value
		if is_instance_valid(_track_sections):
			_track_sections.queue_redraw()
var _track_section_drag_info:= Vector2i(-1, -1)
var _track_section_drag_start: Vector2
var _track_section_textures: Dictionary[WeaponTrack, Texture2D] = {}
var _track_options_popup := PopupMenu.new()
var _track_rename_popup := Popup.new()
var _track_rename_edit := LineEdit.new()

# Time Marker
var _time_marker: Control
# Colors
var _color_font := Color.WHITE
var _color_mono := Color.WHITE
var _color_mono_inv := Color.BLACK
var _color_accent := Color.DEEP_SKY_BLUE

@onready var main_view: Control = %MainView
@onready var tracks_view: Control = %TracksView
@onready var timeline: Control = %Timeline
@onready var h_scroll_bar: Range = %HScrollBar
@onready var add_button: MenuButton = %AddButton
@onready var scroll_bar: ScrollBar = %VScrollBar

func _ready() -> void:
	if not is_instance_valid(owner):
		return

	if owner.has_signal(&"move_selected"):
		owner.connect(&"move_selected", _on_editor_move_selected)
		_setup_complete = true
	else:
		return

	if is_instance_valid(main_view):
		main_view.draw.connect(queue_redraw)

	scroll_bar.hide()
	scroll_bar.value_changed.connect(queue_redraw.unbind(1))
	scroll_bar.value_changed.connect(update_timeline.unbind(1))
	_font = get_theme_default_font()
	_font_size = get_theme_default_font_size()

	h_scroll_bar.value_changed.connect(update_timeline.unbind(1))
	h_scroll_bar.max_value = 60.0
	h_scroll_bar.page = 20.0
	h_scroll_bar.step = 0.1
	h_scroll_bar.changed.connect(func() -> void:
		if is_instance_valid(_track_sections):
			_track_sections.queue_redraw()
	, CONNECT_DEFERRED)
	timeline.gui_input.connect(_on_timeline_input)
	timeline.draw.connect(_draw_timeline)

	tracks_view.draw.connect(_draw_tracks)
	tracks_view.gui_input.connect(_on_tracks_input)
	tracks_view.mouse_exited.connect(func() -> void:
		_hovered_rect = -1
	)

	main_view.show_behind_parent = true

	add_button.about_to_popup.connect(populate_add_button)
	add_button.get_popup().id_pressed.connect(_add_track_from_id)
	populate_add_button()

	var options_popup: PopupMenu = %OptionsButton.get_popup()
	options_popup.clear()
	options_popup.add_check_item("Use Seconds", 0)
	options_popup.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_use_seconds = !_use_seconds
			options_popup.set_item_checked(options_popup.get_item_index(0), _use_seconds)
			timeline.queue_redraw()
	)

	_track_sections_clip = Control.new()
	_track_sections_clip.clip_contents = true
	timeline.add_child(_track_sections_clip)
	_track_sections_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_track_sections = Control.new()
	_track_sections_clip.add_child(_track_sections)
	_track_sections.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_track_sections.draw.connect(_draw_track_sections)
	_track_sections.gui_input.connect(_on_track_sections_gui_input)
	_track_sections.mouse_exited.connect(func() -> void:
		_track_section_hover_index = -1
	)

	_track_rename_popup.add_child(_track_rename_edit)
	_track_rename_edit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_track_rename_edit.select_all_on_focus = true
	_track_rename_popup.about_to_popup.connect(_track_rename_edit.grab_focus)
	_track_rename_edit.text_submitted.connect(func(text: String) -> void:
		var popup_track_index: int = _track_options_popup.get_meta(&"popup_track", -1)
		if popup_track_index < 0 or popup_track_index >= move.tracks.size():
			return
		var track: WeaponTrack = move.tracks[popup_track_index]
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Rename track %d" % popup_track_index)
		ur.add_do_property(track, &"resource_name", text)
		ur.add_undo_property(track, &"resource_name", track.resource_name)
		ur.add_do_method(self, &"update_timeline_and_sections")
		ur.add_undo_method(self, &"update_timeline_and_sections")
		ur.add_do_method(EditorInterface, &"set_object_edited", move, true)
		ur.add_undo_method(EditorInterface, &"set_object_edited", move, true)
		ur.commit_action()
		_track_rename_popup.hide()
	)
	add_child(_track_rename_popup)
	_track_rename_popup.hide()

	add_child(_track_options_popup)
	_track_options_popup.hide()
	_track_options_popup.add_icon_item(
		get_theme_icon(&"Rename", &"EditorIcons"), "Rename", 1, KEY_F2
	)
	_track_options_popup.add_separator()
	_track_options_popup.add_icon_item(
		get_theme_icon(&"Remove", &"EditorIcons"), "Delete", 0, KEY_DELETE
	)
	_track_options_popup.id_pressed.connect(func(id: int) -> void:
		if not move:
			return
		var popup_track_index: int = _track_options_popup.get_meta(&"popup_track", -1)
		if popup_track_index < 0 or popup_track_index >= move.tracks.size():
			return
		match id:
			# Delete track
			0:
				var tracks := move.tracks.duplicate()
				tracks.remove_at(popup_track_index)
				var ur := EditorInterface.get_editor_undo_redo()
				ur.create_action("Remove track %d" % popup_track_index)
				ur.add_do_property(move, &"tracks", tracks)
				ur.add_undo_property(move, &"tracks", move.tracks)
				ur.add_do_method(self, &"update_timeline_and_sections")
				ur.add_undo_method(self, &"update_timeline_and_sections")
				ur.add_do_method(EditorInterface, &"set_object_edited", move, true)
				ur.add_undo_method(EditorInterface, &"set_object_edited", move, true)
				ur.commit_action()
			# Rename track
			1:
				var track: WeaponTrack = move.tracks[popup_track_index]
				_track_rename_popup.transient = true
				_track_rename_popup.exclusive = true
				_track_rename_edit.text = track.resource_name
				var rect: Rect2 = _tracks_rects[popup_track_index]
				rect.position += tracks_view.global_position
				_track_rename_popup.popup_on_parent(rect)
	)

	var compile_button := %CompileButton
	compile_button.pressed.connect(func() -> void:
		if not is_instance_valid(frame_timeline):
			return
		if is_instance_valid(move) and is_instance_valid(handler):
			owner.call(&"simulate_then_seek", roundi(frame_timeline.value))
		if is_instance_valid(_track_sections):
			_track_section_textures.clear()
			_track_sections.queue_redraw.call_deferred()
	)

	_time_marker = Control.new()
	timeline.add_child(_time_marker)
	_time_marker.draw.connect(_draw_time_marker.bind(_time_marker))
	if is_instance_valid(frame_timeline):
		frame_timeline.value_changed.connect(_time_marker.queue_redraw.unbind(1))


func update_timeline() -> void:
	h_scroll_bar.max_value = _get_end()
	timeline.queue_redraw()
	tracks_view.queue_redraw()


func update_timeline_and_sections() -> void:
	update_timeline()
	if is_instance_valid(_track_sections):
		_track_sections.queue_redraw.call_deferred()


func populate_add_button() -> void:
	_tracks_classes.assign({"WeaponTrack": ""})

	var searching: bool = true
	while searching:
		searching = false
		for info: Dictionary in ProjectSettings.get_global_class_list():
			if _tracks_classes.has(info.class):
				continue
			elif _tracks_classes.has(info.base):
				_tracks_classes[info.class] = "" if info.is_abstract else info.path
				searching = true

	add_button.get_popup().clear()
	var id: int = -1

	for target_class: String in _tracks_classes:
		id += 1
		# Skip abstract classes
		if _tracks_classes[target_class].is_empty():
			continue

		add_button.get_popup().add_item(target_class.trim_prefix("WeaponTrack").capitalize(), id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if not is_node_ready():
			await ready
		if not _setup_complete:
			return
		_color_font = get_theme_color(&"font_color", &"Editor")
		_color_mono = get_theme_color(&"mono_color", &"Editor")
		_color_mono_inv = _color_mono.inverted()
		_timeline_bg_color = get_theme_color(&"dark_color_1", &"Editor")
		_color_accent = get_theme_color(&"accent_color", &"Editor")

		%OptionsButton.icon = get_theme_icon(&"GuiTabMenuHl", &"EditorIcons")
		%AddButton.icon = get_theme_icon(&"Add", &"EditorIcons")
		%CompileButton.icon = get_theme_icon(&"Reload", &"EditorIcons")

		_timeline_marker_bg_stylebox.bg_color = _color_accent

		_track_section_stylebox.bg_color = _color_accent
		_track_section_stylebox.set_border_width_all(2)
		_track_section_stylebox.border_color = _track_section_stylebox.bg_color.lerp(_color_mono, 0.2)

		var btn_stylebox := get_theme_stylebox(&"normal", &"Button")
		if btn_stylebox is StyleBoxFlat:
			_timeline_marker_bg_stylebox.set_corner_radius_all(btn_stylebox.corner_radius_bottom_left)
			_track_section_stylebox.set_corner_radius_all(btn_stylebox.corner_radius_bottom_left)

		_shade_texture = get_theme_icon(&"scroll_hint_vertical", &"ScrollContainer")
		_shade_color = get_theme_color(&"scroll_hint_vertical_color", &"ScrollContainer")
		if is_instance_valid(_track_options_popup) and _track_options_popup.item_count > 0:
			_track_options_popup.set_item_icon(
				_track_options_popup.get_item_index(0),
				get_theme_icon(&"Remove", &"EditorIcons")
			)
			_track_options_popup.set_item_icon(
				_track_options_popup.get_item_index(1),
				get_theme_icon(&"Rename", &"EditorIcons")
			)


func _draw() -> void:
	if scroll_bar.visible:
		if scroll_bar.value > 0.0:
			var r := main_view.get_rect()
			r = r.grow_side(SIDE_TOP, -_time_ruler_height)
			r.size.y = _shade_texture.get_height()
			draw_texture_rect(_shade_texture, r, false, _shade_color)
		if (scroll_bar.value + scroll_bar.page) < scroll_bar.max_value:
			var r := main_view.get_rect()
			r = r.grow_side(SIDE_TOP, _time_ruler_height - r.size.y)
			r.size.y = -r.size.y
			draw_texture_rect(_shade_texture, r, false, _shade_color)


func _on_frame_processed() -> void:
	update_timeline()
	_time_marker.queue_redraw()


func _add_track_from_id(id: int) -> void:
	if _tracks_classes.is_empty():
		return

	if move:
		if move.tracks.is_read_only():
			move.tracks = []

		var track: WeaponTrack = load(_tracks_classes.values()[id]).new()
		track.resource_name = str(_tracks_classes.keys()[id]).trim_prefix("Weapon").trim_prefix("Track").capitalize()
		var new_tracks := move.tracks.duplicate()
		new_tracks.append(track)
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Add new track")
		ur.add_do_property(move, &"tracks", new_tracks)
		ur.add_undo_property(move, &"tracks", move.tracks)
		ur.add_do_method(self, &"update_timeline_and_sections")
		ur.add_undo_method(self, &"update_timeline_and_sections")
		ur.add_do_method(EditorInterface, &"set_object_edited", move, true)
		ur.add_undo_method(EditorInterface, &"set_object_edited", move, true)
		ur.add_do_method(EditorInterface, &"edit_resource", track)
		ur.commit_action()


func _draw_timeline() -> void:
	var time_offset: float = h_scroll_bar.value + TIMELINE_OFFSET_FRAMES
	var time_offset_sub: float = wrapf(fmod(time_offset, 1.0), 0.0, 1.0)
	_pixels_per_frame = timeline.size.x / h_scroll_bar.page

	var timeline_rect: Rect2 = timeline.get_rect()

	# Draw timeline ruler
	_time_ruler_height = timeline_rect.size.y - tracks_view.size.y
	timeline_rect.position = Vector2.ZERO
	timeline_rect.size.y = _time_ruler_height
	var odd: bool = false
	timeline.draw_rect(timeline_rect, _timeline_bg_color.lerp(_color_mono_inv, 0.4))
	# Offset timeline rect by ruler
	timeline_rect.position.y = timeline_rect.end.y
	timeline_rect.size.y = timeline.size.y - _time_ruler_height

	# Draw timeline bars
	var bar_rect := timeline_rect
	bar_rect.size.y = TRACK_HEIGHT
	bar_rect.position.y -= scroll_bar.get_value()

	var track_index: int = 0

	for i: int in range(bar_rect.position.y, timeline.size.y, TRACK_HEIGHT):
		bar_rect.position.y = max(i, _time_ruler_height)
		bar_rect.size.y = min(bar_rect.size.y, timeline.size.y - i)
		if odd:
			timeline.draw_rect(bar_rect, _timeline_bg_color.lerp(_color_mono_inv, 0.08))
		else:
			timeline.draw_rect(bar_rect, _timeline_bg_color.lerp(_color_mono_inv, -0.08))
		odd = not odd
		track_index += 1

	# Darken area before frame 0
	if time_offset < 0.0:
		timeline.draw_rect(
			Rect2(timeline_rect.position, Vector2(absf(time_offset) * _pixels_per_frame, timeline_rect.size.y)),
			_timeline_bg_color.lerp(_color_mono_inv, 0.4)
		)

	var main_split_interval: int = maxi(roundi(100.0 / _pixels_per_frame), 1)
	var split_color: Color = _color_mono_inv

	# Draw timeline splits
	for local_frame: int in range(ceili(h_scroll_bar.page) + 2):
		var frame: int = floori(local_frame + time_offset)
		if frame < 0:
			continue
		var point := Vector2((local_frame - time_offset_sub) * _pixels_per_frame, 0.0)
		var line_text: String = ""

		if frame % main_split_interval == 0:
			split_color.a = 0.7
			var time: float = float(frame) / Engine.physics_ticks_per_second
			if _use_seconds:
				line_text = "%.1fs" % time
				if time < 1.0:
					line_text = "%dms" % (time * 1000)
					if is_zero_approx(time):
						line_text = "0"
			else:
				line_text = "%d" % frame

			var paragraph := TextParagraph.new()
			paragraph.add_string(line_text, _font, _font_size)
			var off := Vector2(point.x, _time_ruler_height * 0.5) - (paragraph.get_size() * 0.5)
			paragraph.draw(timeline.get_canvas_item(), off, _color_font)
		else:
			split_color.a = 0.2

		point.y = _time_ruler_height
		timeline.draw_line(point, point + Vector2.DOWN * timeline.size.y, split_color)

	# Color area after move end frame
	if is_instance_valid(frame_timeline):
		if frame_timeline.end_frame <= ceili(time_offset + h_scroll_bar.page):
			var rect := timeline_rect
			var end_pos_ratio: float = (
				float(frame_timeline.end_frame) - h_scroll_bar.value
			) / h_scroll_bar.page
			rect.position.x = lerpf(rect.position.x, rect.end.x, end_pos_ratio)
			timeline.draw_rect(rect, _timeline_bg_color.lerp(_color_mono_inv, 0.4))

	# Move track sections and time marker
	_track_sections_clip.position.y = _time_ruler_height
	_track_sections.position.x = -time_offset * _pixels_per_frame
	_track_sections.position.y = -scroll_bar.get_value()
	if is_instance_valid(frame_timeline):
		_time_marker.position.x = (roundi(frame_timeline.value) - time_offset) * _pixels_per_frame
	else:
		_time_marker.position.x = (maxi(handler.frame, 0) - time_offset) * _pixels_per_frame


func _draw_time_marker(control: Control) -> void:
	if not move or not is_instance_valid(handler):
		return
	var time_offset: float = h_scroll_bar.value + TIMELINE_OFFSET_FRAMES

	_time_marker_dragger.position.x = -TIME_MARKER_POINTER_WIDTH
	_time_marker_dragger.size = Vector2.ONE * TIME_MARKER_POINTER_WIDTH
	_time_marker_dragger.size.y = _time_ruler_height
	_time_marker_dragger = _time_marker_dragger.grow(4.0)
	_time_marker_dragger.position.y = 0.0

	control.draw_line(
		Vector2.ZERO,
		Vector2.DOWN * timeline.size.y,
		_color_accent,
		TIME_MARKER_LINE_WIDTH
	)

	var line_text: String = ""
	var frame: int = maxi(handler.frame, 0)
	if is_instance_valid(frame_timeline):
		frame = roundi(frame_timeline.value)
	if _use_seconds:
		var time: float = float(frame) / Engine.physics_ticks_per_second
		line_text = "%.1fs" % time
		if time < 1.0:
			line_text = "%dms" % (time * 1000)
			if is_zero_approx(time):
				line_text = "0"
	else:
		line_text = "%d" % frame
	var rect := _string_rect(line_text, Vector2(0.0, _time_ruler_height * 0.5)).grow(3.0)
	rect.position.y = 0.0
	rect.size.y = _time_ruler_height
	control.draw_style_box(_timeline_marker_bg_stylebox, rect)

	# Draw frame text
	var paragraph := TextParagraph.new()
	paragraph.width = rect.size.x
	paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER
	paragraph.add_string(line_text, _font, _font_size)
	var off := Vector2(rect.position.x, (rect.size.y - paragraph.get_size().y) * 0.5)
	paragraph.draw(control.get_canvas_item(), off, _color_font)


func _on_timeline_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed() and not _seeking:
			# Zoom in or scroll right
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if Input.is_key_pressed(KEY_CTRL):
					h_scroll_bar.page = maxf(h_scroll_bar.page - 1.0, 4.0)
				else:
					h_scroll_bar.value -= h_scroll_bar.page * 0.05
				update_timeline()
				timeline.accept_event()
			# Zoom out or scroll left
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if Input.is_key_pressed(KEY_CTRL):
					h_scroll_bar.page += 1.0
				else:
					h_scroll_bar.value += h_scroll_bar.page * 0.05
				update_timeline()
				timeline.accept_event()

		# Seeking
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.y < _time_ruler_height:
				_seeking = event.is_pressed()
			elif not event.is_pressed():
				_seeking = false

			if _seeking:
				var seek_time: float = lerpf(
					h_scroll_bar.value,
					h_scroll_bar.value + h_scroll_bar.page,
					event.position.x / timeline.size.x
				)
				if is_instance_valid(frame_timeline):
					frame_timeline.value = roundi(seek_time) + TIMELINE_OFFSET_FRAMES
				else:
					owner.call(&"_seek_frame", roundi(seek_time) + TIMELINE_OFFSET_FRAMES)
			timeline.accept_event()

	elif event is InputEventMouseMotion:
		if _seeking:
			var seek_time: float = lerpf(
				h_scroll_bar.value,
				h_scroll_bar.value + h_scroll_bar.page,
				event.position.x / timeline.size.x
			)
			if is_instance_valid(frame_timeline):
				frame_timeline.value = roundi(seek_time) + TIMELINE_OFFSET_FRAMES
			else:
				owner.call(&"_seek_frame", roundi(seek_time) + TIMELINE_OFFSET_FRAMES)
			timeline.accept_event()


func _draw_tracks() -> void:
	if not move:
		return

	var r: Rect2 = tracks_view.get_rect()
	r.position = Vector2.ZERO

	tracks_view.custom_minimum_size.x = 128.0

	r.position.y -= scroll_bar.get_value()
	r.size.y = TRACK_HEIGHT

	var track_count: int = move.tracks.size()
	scroll_bar.max_value = track_count * TRACK_HEIGHT
	scroll_bar.page = tracks_view.size.y

	var new_visibility: bool = scroll_bar.page < scroll_bar.max_value
	if scroll_bar.visible != new_visibility:
		scroll_bar.visible = new_visibility
		queue_redraw()

	var track_index: int = -1

	_tracks_rects.clear()

	for i: int in range(r.position.y, tracks_view.size.y, TRACK_HEIGHT):
		track_index += 1
		if track_index >= track_count:
			continue

		var hovered: bool = track_index == _hovered_rect
		var track: WeaponTrack = move.tracks[track_index]
		if not track.changed.is_connected(tracks_view.queue_redraw):
			track.changed.connect(tracks_view.queue_redraw)

		r.position.y = i
		_tracks_rects.append(r)
		var track_rect := r.grow_individual(-1.0, -1.0, 4.0, -1.0)
		var stylebox := get_theme_stylebox(&"hover" if hovered else &"normal", &"Button")
		tracks_view.draw_style_box(stylebox, track_rect)

		# Draw track debug color
		var color_rect := track_rect
		color_rect.size.x = 4
		color_rect.position.x = r.end.x - color_rect.size.x
		tracks_view.draw_rect(color_rect, track.debug_color)

		# Draw track name
		var line_text: String = track.resource_name
		var paragraph := TextParagraph.new()
		paragraph.width = track_rect.size.x
		paragraph.add_string(line_text, _font, _font_size)
		var off := Vector2(
			track_rect.position.x,
			track_rect.get_center().y - (paragraph.get_size().y / 2.0)
		)
		off.x += stylebox.content_margin_left
		paragraph.draw(tracks_view.get_canvas_item(), off, _color_font)


func _on_tracks_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			# Scroll up
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				scroll_bar.value -= 10.0
				update_timeline()
				tracks_view.accept_event()
			# Scroll down
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				scroll_bar.value += 10.0
				update_timeline()
				tracks_view.accept_event()

			elif move and _hovered_rect > -1:
				if event.button_index == MOUSE_BUTTON_LEFT:
					EditorInterface.inspect_object(move.tracks[_hovered_rect])
					tracks_view.accept_event()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					var btn_rect := tracks_view.get_global_rect()
					btn_rect.position += tracks_view.get_local_mouse_position()
					_track_options_popup.set_meta(&"popup_track", _hovered_rect)
					_track_options_popup.popup_on_parent(btn_rect)
					tracks_view.accept_event()

	elif event is InputEventMouseMotion:
		var is_hovering: bool = false
		for i: int in range(_tracks_rects.size()):
			if _tracks_rects[i].has_point(event.position):
				_hovered_rect = i
				is_hovering = true
				if move:
					tracks_view.tooltip_text = move.tracks[i].resource_name
					var script: Script = move.tracks[i].get_script() as Script
					if script:
						var script_class: String = script.get_global_name()
						tracks_view.tooltip_text += "\nType: %s" % (
							script.resource_path if script_class.is_empty() else script_class
						)

		if not is_hovering:
			_hovered_rect = -1


func _draw_track_sections() -> void:
	if not move:
		return

	var container_rect := Rect2(Vector2.ZERO, _track_sections.size)
	var hovering: bool = false
	var fps: int = Engine.physics_ticks_per_second
	# Draw track sections
	_track_section_rects.clear()
	for i: int in range(move.tracks.size()):
		var track := move.tracks[i]
		if not track.changed.is_connected(_track_sections.queue_redraw):
			track.changed.connect(_track_sections.queue_redraw)
		var duration: int = track.get_duration()
		var track_color := Color.DIM_GRAY
		var script: Script = track.get_script() as Script
		var preview_resource: String = ""
		var track_text: String = ""
		if is_instance_valid(script):
			match script.get_global_name():
				&"WeaponTrackHitBox":
					track_color = Color.FIREBRICK
					track_text = type_convert(track.get(&"bone_name"), TYPE_STRING)
				&"WeaponTrackAudio":
					track_color = Color.GOLD
					preview_resource = "stream:resource_path"
					#HACK get voice pack duration from handler's in editor
					#if type_convert(track.get(&"use_voice_pack"), TYPE_BOOL):
						#var clip: StringName = type_convert(track.get(&"clip_name"), TYPE_STRING_NAME)
						#var voice_pack: CharacterVoicePack = handler.character.voice_pack
						#if voice_pack:
							#var stream := voice_pack.get_voice(clip)
							#if stream:
								#duration = ceili(stream.get_length() * fps)
								#preview_resource = stream.resource_path
				&"WeaponTrackVibration":
					var preset: Resource = track.get(&"preset")
					if is_instance_valid(preset):
						track_text = type_convert(preset.resource_name, TYPE_STRING)

		var track_rect := Rect2(Vector2.ZERO, Vector2(0.0, TRACK_HEIGHT))
		track_rect.position.x += track.start_frame * _pixels_per_frame
		track_rect.position.y += TRACK_HEIGHT * i
		track_rect.size.x = duration * _pixels_per_frame
		if duration == 0:
			track_rect.size.x = maxf(_pixels_per_frame * 0.5, 8.0)
			track_rect.position.x -= track_rect.size.x * 0.5
		# Infinite duration
		elif duration < 0:
			track_rect.size.x = _track_sections.size.x

		# Draw container
		track_color = track_color.lerp(Color(track.debug_color, 1.0), track.debug_color.a)
		if i == _track_section_hover_index || i == _track_section_drag_info[0]:
			hovering = true
			track_color = track_color.lerp(_color_mono, 0.5)
		var sb := _track_section_stylebox.duplicate()
		sb.bg_color = track_color
		sb.border_color = sb.bg_color.lerp(_color_mono, 0.6)
		if duration == 0:
			var center := track_rect.get_center()
			_track_sections.draw_line(
				Vector2(center.x, track_rect.position.y),
				Vector2(center.x, track_rect.end.y),
				sb.border_color,
				4.0
			)
			var radius: float = minf(_pixels_per_frame * 0.5, _time_ruler_height * 0.25)
			_track_sections.draw_circle(center, radius, sb.border_color, false, 4.0, true)
			_track_sections.draw_circle(center, radius, sb.bg_color, true, -1.0, true)
		else:
			_track_sections.draw_style_box(sb, track_rect.grow(-2))
		# Draw preview
		if not preview_resource.is_empty():
			if _track_section_textures.has(track):
				_track_sections.draw_texture_rect(
					_track_section_textures[track],
					track_rect.grow(-2),
					false,
					Color(Color.WHITE, 0.4)
				)
			else:
				var v: Variant = track.get_indexed(preview_resource)
				if preview_resource.begins_with("res://"):
					v = preview_resource
				if typeof(v) != TYPE_NIL:
					EditorInterface.get_resource_previewer().queue_resource_preview(
						v,
						self,
						&"_track_preview_generated",
						track
					)
		# Draw track text
		var text_rect := track_rect.grow(-6.0)
		_track_sections.draw_string(
			_font,
			Vector2(text_rect.position.x, text_rect.end.y),
			track_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			text_rect.size.x,
			_font_size,
			_color_font
		)
		_track_section_rects.append(track_rect.abs().grow(2.0))
		# Increase size to encompass all rects
		_track_sections.size = _track_sections.size.max(track_rect.end)
	_track_sections.mouse_default_cursor_shape = CURSOR_MOVE if hovering else CURSOR_ARROW


func _on_track_sections_gui_input(event: InputEvent):
	if event is InputEventMouse:
		var mouse_frame: int = roundi(event.position.x / _pixels_per_frame)
		if event is InputEventMouseButton:
			if not event.is_pressed():
				if _track_section_drag_info[0] != -1:
					if _track_section_drag_start.distance_squared_to(event.position) < 2.0:
						EditorInterface.edit_resource(move.tracks[_track_section_drag_info[0]])
					_track_section_drag_info[0] = -1
					_track_sections.queue_redraw()
					_track_sections.accept_event()
				return
			if event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
				if _track_section_hover_index >= 0:
					if _track_section_drag_info[0] != _track_section_hover_index:
						_track_section_drag_info[0] = _track_section_hover_index
						_track_section_drag_info[1] = (
							_get_track_section_start_frame(_track_section_hover_index) - mouse_frame
						)
						_track_section_drag_start = event.position
					_track_sections.accept_event()
		elif event is InputEventMouseMotion:
			if _track_section_drag_info[0] >= 0:
				if move and _track_section_drag_info[0] < move.tracks.size():
					var track := move.tracks[_track_section_drag_info[0]]
					mouse_frame += _track_section_drag_info[1]
					var ur := EditorInterface.get_editor_undo_redo()
					ur.create_action("Set start_frame", UndoRedo.MERGE_ENDS)
					ur.add_do_property(track, &"start_frame", mouse_frame)
					ur.add_undo_property(track, &"start_frame", track.start_frame)
					ur.add_do_method(EditorInterface, &"set_object_edited", move, true)
					ur.add_undo_method(EditorInterface, &"set_object_edited", move, true)
					ur.commit_action()
			else:
				for i: int in range(_track_section_rects.size()):
					if _track_section_rects[i].has_point(event.position):
						_track_section_hover_index = i
						_track_sections.accept_event()
						return
				_track_section_hover_index = -1


func _get_track_section_start_frame(index: int) -> int:
	if move and index < move.tracks.size():
		return move.tracks[index].start_frame
	return 0


func _on_editor_move_selected(p_move: WeaponMove, p_handler: WeaponHandler) -> void:
	handler = p_handler
	move = p_move
	_track_section_textures.clear()


func _string_rect(text: String, pos: Vector2, fsize := _font_size) -> Rect2:
	var text_size: Vector2 = _font.get_string_size(text, 0, -1, fsize)
	pos -= (text_size * Vector2(0.5, 0.5))
	pos.y += _font.get_ascent(fsize)
	return Rect2(pos + (text_size * Vector2.UP), text_size)


func _track_preview_generated(path: String, preview: Texture2D, thumb: Texture2D, data: Variant) -> void:
	if is_instance_valid(preview):
		_track_section_textures[data] = preview


func _get_end() -> int:
	var frame: int = ceili(_animation_length * Engine.physics_ticks_per_second)
	if is_instance_valid(frame_timeline):
		frame = maxi(frame, maxi(frame_timeline.end_frame, frame_timeline.max_value))
	if move:
		for track: WeaponTrack in move.tracks:
			frame = maxi(frame, track.start_frame + track.get_duration())
	return frame + 5
