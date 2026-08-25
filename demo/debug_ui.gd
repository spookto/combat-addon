extends CanvasLayer

@onready var speed_label: Label = %SpeedLabel
@onready var speed_slider: Slider = %SpeedSlider
@onready var jump_c_check_box: CheckBox = %JumpCCheckBox
@onready var weapon_handler: WeaponHandler = %WeaponHandler

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	speed_slider.value_changed.connect(func(value: float) -> void:
		speed_label.text = "Weapon Speed %.1f" % value
		weapon_handler.speed_scale = value
	)
	speed_slider.value = 1.0

	jump_c_check_box.toggled.connect(func(value: bool) -> void:
		owner.set(&"jump_cancels_all", value)
	)
	jump_c_check_box.set_pressed_no_signal(owner.get(&"jump_cancels_all"))
