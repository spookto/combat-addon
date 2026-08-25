class_name WeaponMovesLabel
extends RichTextLabel

static var localization_support: bool = false


static func get_weapon_moves_rich_text(weapon: WeaponInformation) -> String:
	var out: String = "[table=2]"

	for move: WeaponMove in weapon.moves:
		if move.visual_flags & WeaponMove.VisualFlag.EXCLUDE_IF_ROOT:
			continue
		out += get_move_rich_text(move)
	out += "[/table]"

	out = out.format({"weapon": weapon.identifier.to_upper()})

	if ProjectSettings.has_setting("addons/combat_addon/settings_path"):
		var settings_path: String = ProjectSettings.get_setting_with_override("addons/combat_addon/settings_path")
		if ResourceLoader.exists(settings_path):
			var settings: CombatAddonSettings = ResourceLoader.load(settings_path) as CombatAddonSettings
			out = out.format(_get_icons_format_dict(settings))

	return out


static func get_move_rich_text(move: WeaponMove, depth: int = 0) -> String:
	var out: String = ""
	if move.hidden:
		for child_move: WeaponMove in move.next_moves:
			if child_move.visual_exclude_if_child:
				continue
			out += get_move_rich_text(child_move, depth + 1)
		return out

	out += "-\t".repeat(depth + 1)
	var move_name: String = move.name
	if localization_support:
		"WPNMOVE_{weapon}_%s" % move.name.to_upper()

	out += "[cell shrink=false expand=1]%s[/cell]" % move_name
	var input_line: String = _get_attack_input_string(move)

	if depth <= 0:
		input_line += " " + move.get_condition_text()
	else:
		input_line += " " + move.get_delay_text()
		input_line = "{next}" + input_line

	input_line = "{empty}".repeat(maxi(depth - 1, 0)) + input_line
	input_line += "{empty}"

	out += "[cell shrink=false expand=1]" + input_line + "[/cell]"
	out += "\n"

	#HACK Push child moves 1 tile forward when including dash input
	if move.is_condition(WeaponMove.Condition.DASH):
		depth += 1

	#HACK Push child moves 1 tile forward when including jump input
	if move.is_condition(WeaponMove.Condition.JUMP):
		depth += 1

	#HACK Push child moves 1 tile forward when including move stick input
	if move.is_condition(WeaponMove.Condition.MOVE_STICK_FORWARD):
		depth += 1

	var visible_children: Array[WeaponMove] = move.get_visible_next_moves()
	for child_move: WeaponMove in move.next_moves:
		if visible_children.has(child_move):
			out += get_move_rich_text(child_move, depth + 1)
	return out


static func _get_attack_input_string(move: WeaponMove) -> String:
	if move.exclude_from_movelist:
		return ""

	var string: String = "{hold}" if move.visual_hold else ""
	var input: int = move.get_draw_input()
	match input:
		WeaponMove.MoveInput.NONE:
			pass
		WeaponMove.MoveInput.LIGHT:
			string = "{light}" + string
		WeaponMove.MoveInput.HEAVY:
			string = "{heavy}" + string
		_:
			string = ("{extra%d}" % (input - WeaponMove.MoveInput.HEAVY)) + string

	if move.is_condition(WeaponMove.Condition.DASH):
		string = "{dash}" + string

	if move.is_condition(WeaponMove.Condition.JUMP):
		string = "{jump}" + string

	if move.is_condition(WeaponMove.Condition.MOVE_STICK_FORWARD):
		string = "{move_forward}" + string

	for child_move: WeaponMove in move.next_moves:
		if child_move.hidden and not child_move.visual_exclude_if_child:
			string += _get_attack_input_string(child_move)

	return string


static func _get_icons_format_dict(settings: CombatAddonSettings) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id: String in ["empty", "next", "jump", "dash", "light", "heavy", "extra1", "extra2", "extra3", "extra4"]:
		var icon: Texture2D = settings.get("movelist_icon_%s" % id) as Texture2D
		if icon:
			# Godot v4.7 and above support image sizing relative to rich text font size
			if Engine.get_version_info().hex >= 0x040700:
				out[id] = "[img height=1em]%s[/img]" % icon.resource_path
			# Old Godot version, fallback to pixel scaling
			else:
				out[id] = "[img height=16px]%s[/img]" % icon.resource_path
		else:
			out[id] = ""
	return out

@export var weapon: WeaponInformation


func _ready() -> void:
	if weapon:
		append_text(get_weapon_moves_rich_text(weapon))
