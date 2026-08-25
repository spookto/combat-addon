@tool
class_name WeaponMeshInstance
extends MeshInstance3D

@export var weapon_handler: WeaponHandler
@export var visual_hands: VisualInstance3D
@export var visual_legs: VisualInstance3D
@export_group("Delay Visuals", "delay_")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var delay_enabled: bool = true
@export var delay_particles: GPUParticles3D
@export var delay_glow: Color = Color.WHITE

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "WeaponInformation", PROPERTY_USAGE_EDITOR)
var delay_preview: WeaponInformation
@export_tool_button("Preview", "PreviewSun") var tool_preview_delay := _spawn_delay_particles

var _active_info: WeaponInformation = null
var _holster_mesh: MeshInstance3D
var _holster_attachment: ModifierBoneTarget3D
var _holster_attached_mesh: MeshInstance3D
var _skeleton: Skeleton3D = null
var _keep_holster: bool = false
var _can_hide_parts: bool = false
var _delay_tween: Tween

func _init() -> void:
	gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	layers = 0b10

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_skeleton = get_node(skeleton) as Skeleton3D
	if not is_instance_valid(_skeleton):
		return

	if not is_instance_valid(weapon_handler):
		return

	if not _skeleton.is_node_ready():
		await _skeleton.ready

	_can_hide_parts = is_instance_valid(visual_hands) and is_instance_valid(visual_legs)

	_holster_mesh = MeshInstance3D.new()
	_skeleton.add_child(_holster_mesh)
	_holster_mesh.layers = self.layers
	_holster_mesh.name = "HolsterMesh"
	_holster_mesh.skeleton = ^".."
	_holster_mesh.material_overlay = material_overlay
	_holster_mesh.set_instance_shader_parameter(&"uv_offset_multiplier", 0.0)

	_holster_attachment = ModifierBoneTarget3D.new()
	_holster_attachment.name = "HolsterBoneAttachment"
	_skeleton.add_child(_holster_attachment)
	_holster_attached_mesh = MeshInstance3D.new()
	_holster_attached_mesh.layers = self.layers
	_holster_attached_mesh.name = "HolsterAttachmentMesh"
	_holster_attached_mesh.material_overlay = material_overlay
	_holster_attached_mesh.set_instance_shader_parameter(&"uv_offset_multiplier", 0.0)
	_holster_attachment.add_child(_holster_attached_mesh)

	weapon_handler.active_weapon_changed.connect(_on_active_weapon_changed)
	weapon_handler.move_started.connect(_on_move_started, CONNECT_DEFERRED)
	weapon_handler.move_stopped.connect(_on_move_stopped, CONNECT_DEFERRED)
	if delay_enabled:
		weapon_handler.delay_started.connect(_delay_visuals.bind(true))
		weapon_handler.delay_ended.connect(_delay_visuals.bind(false))

	_on_active_weapon_changed.call_deferred()
	_on_move_stopped()


func _on_active_weapon_changed() -> void:
	#TODO Pass information through signal instead
	_active_info = weapon_handler.active_information
	if _active_info == null:
		visual_hands.visible = true
		visual_legs.visible = true
		_holster_attachment.hide()
		mesh = null
		return

	mesh = _active_info.weapon_mesh
	skin = _get_skin_from_mesh(mesh)

	if _active_info.holster_keep_previous:
		_keep_holster = true
	if _keep_holster:
		return
	_holster_mesh.mesh = _active_info.holster_mesh
	_holster_mesh.skin = _get_skin_from_mesh(_holster_mesh.mesh)

	_holster_attached_mesh.mesh = null

	if _can_hide_parts:
		visual_hands.visible = not _active_info.holster_hide_hands
		visual_legs.visible = not _active_info.holster_hide_legs

	match _active_info.holster_type:
		WeaponInformation.HolsterType.HIDE, WeaponInformation.HolsterType.EQUIP_MESH:
			_holster_attachment.hide()
		WeaponInformation.HolsterType.BONE_ATTACHMENT_MESH:
			_holster_attachment.show()
			_holster_attachment.bone_name = _active_info.holster_bone
			_holster_attached_mesh.transform = _active_info.holster_bone_transform
			_holster_attached_mesh.reset_physics_interpolation()
			_holster_attached_mesh.mesh = _holster_mesh.mesh
			_holster_mesh.mesh = null


func _on_move_started(move: WeaponMove) -> void:
	if move != null and move.behaviour_no_mesh_visuals:
		return

	_visible_state(true)
	if _keep_holster:
		return
	_holster_mesh.hide()
	_holster_attached_mesh.hide()


func _on_move_stopped() -> void:
	_visible_state(false)
	_holster_mesh.show()
	_holster_attached_mesh.show()


func _visible_state(equipped: bool) -> void:
	# No weapon is equipped
	if not _active_info:
		if _can_hide_parts:
			# Show full body
			visual_hands.visible = true
			visual_legs.visible = true
		visible = false
		return

	visible = equipped
	if _can_hide_parts:
		visual_hands.visible = not (
			_active_info.equip_hide_hands if equipped else _active_info.holster_hide_hands
			)
		visual_legs.visible = not (
			_active_info.equip_hide_legs if equipped else _active_info.holster_hide_legs
			)


func _get_skin_from_mesh(source_mesh: Mesh) -> Skin:
	if not source_mesh:
		return null
	if source_mesh.has_meta(&"skin"):
		return source_mesh.get_meta(&"skin")
	return null


func _delay_visuals(active: bool) -> void:
	if _delay_tween:
		_delay_tween.custom_step(1000.0)
	if not active:
		return
	if not _active_info:
		return
	_delay_tween = create_tween().set_parallel()
	var lamba: Callable = func(color: Color) -> void:
		set_instance_shader_parameter(&"color_override", color)
	var end: Color = delay_glow
	end.a = 0.0
	_delay_tween.tween_method(lamba, delay_glow, end, 0.2)

	for i: int in range(8):
		_delay_tween.tween_callback(_spawn_delay_particles).set_delay(0.01 * i)


func _spawn_delay_particles() -> void:
	if Engine.is_editor_hint() and delay_preview:
		_active_info = delay_preview
	if not _active_info:
		return
	for bone: StringName in _active_info.delay_visual_bones:
		var t: Transform3D = _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
		t *= _active_info.delay_visual_bones[bone]
		var flags: int = GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
		delay_particles.emit_particle(
			t, t.basis.y, Color.RED, Color.RED, flags
		)


func _validate_property(property: Dictionary) -> void:
	# Only validate in editor, allows afterimages to have weapons
	if not Engine.is_editor_hint():
		return
	match property.name:
		&"visible", &"mesh", &"layers", &"gi_mode", &"skin":
			property.usage &= ~PROPERTY_USAGE_STORAGE
