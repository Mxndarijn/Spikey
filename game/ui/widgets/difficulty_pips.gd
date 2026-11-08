class_name DifficultyPips
extends Control
## Difficulty as five small pills: filled ink up to the level, outlined after.

const COUNT := 5
const PIP := Vector2(18, 10)
const GAP := 3.0

var level := 1:
	set(value):
		level = clampi(value, 0, COUNT)
		queue_redraw()


func _init(p_level: int = 1) -> void:
	level = p_level
	custom_minimum_size = Vector2(COUNT * PIP.x + (COUNT - 1) * GAP, PIP.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for i in COUNT:
		var r := Rect2(Vector2(i * (PIP.x + GAP), 0), PIP)
		var box := StyleBoxFlat.new()
		box.bg_color = UiTokens.INK_LINE if i < level else UiTokens.PANEL
		box.border_color = UiTokens.INK_LINE
		box.set_border_width_all(2)
		box.set_corner_radius_all(int(PIP.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, r)
