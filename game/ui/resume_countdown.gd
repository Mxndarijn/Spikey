class_name ResumeCountdown
extends Label
## The big count over the frozen room: 3, 2, 1 after Resume, 5 to 1 after a
## revive.

const SIZE := 120
## A wider halo than the score's, for the bigger digits.
const HALO := 12


func _init() -> void:
	theme_type_variation = &"HudScore"
	add_theme_font_size_override("font_size", SIZE)
	add_theme_constant_override("outline_size", HALO)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = "3"
	visible = false


## Shows `n`; 0 hides it.
func show_count(n: int) -> void:
	visible = n > 0
	if n > 0:
		text = str(n)
