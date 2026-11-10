class_name ResumeCountdown
extends Label
## The 3, 2, 1 big over the frozen room after Resume.

const SIZE := 120


func _init() -> void:
	theme_type_variation = &"RoomScore"
	add_theme_font_size_override("font_size", SIZE)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = "3"
	visible = false


## Shows `n` (3, 2, 1); 0 hides it.
func show_count(n: int) -> void:
	visible = n > 0
	if n > 0:
		text = str(n)
