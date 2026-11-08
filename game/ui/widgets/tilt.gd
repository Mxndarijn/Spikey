class_name Tilt
extends Control
## Holds one control turned by a few degrees (Sticker Pop stickers and titles).
## Containers reset the rotation of their direct children, so the tilted control
## sits inside this plain Control, which takes its child's minimum size.

var degrees := 0.0:
	set(value):
		degrees = value
		_place()

var _child: Control


func _init(child: Control, p_degrees: float) -> void:
	_child = child
	degrees = p_degrees
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = child.size_flags_horizontal
	size_flags_vertical = child.size_flags_vertical
	add_child(child)
	child.minimum_size_changed.connect(_fit)
	resized.connect(_place)
	_fit()


func content() -> Control:
	return _child


func _fit() -> void:
	custom_minimum_size = _child.get_combined_minimum_size()
	_place()


func _place() -> void:
	if _child == null:
		return
	_child.position = Vector2.ZERO
	_child.size = size
	_child.pivot_offset = size / 2.0
	_child.rotation_degrees = degrees
