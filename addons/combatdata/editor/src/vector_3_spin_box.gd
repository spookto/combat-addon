@tool
extends Control

signal value_changed(value: Vector3)

@export var min_value: Vector3 = Vector3.ZERO:
	set(value):
		min_value = value
		for i: int in range(3):
			max_value[i] = max(min_value[i], max_value[i])
			_spin_boxes[i].min_value = min_value[i]
		value = value
@export var max_value: Vector3 = Vector3.ONE:
	set(value):
		for i: int in range(3):
			max_value[i] = max(min_value[i], value[i])
			_spin_boxes[i].max_value = max_value[i]
		value = value

@export var step: float = 1.0:
	set(value):
		step = value
		for i: int in range(3):
			_spin_boxes[i].step = step

@export var value: Vector3:
	set(new_value):
		for i: int in range(3):
			value[i] = clamp(new_value[i], min_value[i], max_value[i])
			_spin_boxes[i].set_value_no_signal(value[i])

var _spin_boxes: Array[EditorSpinSlider] = [
	EditorSpinSlider.new(),
	EditorSpinSlider.new(),
	EditorSpinSlider.new()
]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var i: int = 0
	for spin_slider: EditorSpinSlider in _spin_boxes:
		add_child(spin_slider)
		spin_slider.control_state = EditorSpinSlider.CONTROL_STATE_HIDE
		spin_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin_slider.value_changed.connect(_update_vector_value.unbind(1))

		match i:
			0:
				spin_slider.label = "x"
			1:
				spin_slider.label = "y"
			2:
				spin_slider.label = "z"
			_:
				spin_slider.label = "w"
		i += 1


func set_value(new_value: Vector3) -> void:
	set_value_no_signal(new_value)
	value_changed.emit(value)


func set_value_no_signal(new_value: Vector3) -> void:
	value = new_value


func _update_vector_value() -> void:
	var v: Vector3 = Vector3.ZERO
	for i: int in range(3):
		v[i] = _spin_boxes[i].value

	value = v
	value_changed.emit(value)
