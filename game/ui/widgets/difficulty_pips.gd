class_name DifficultyPips
extends Control
## Difficulty as five small flat pills: ink up to the level, the soft edge
## colour after it.

const COUNT := 5
const PIP := Vector2(16, 8)
const GAP := 4.0

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
		box.bg_color = UiTokens.INK_LINE if i < level else UiTokens.EDGE
		box.set_corner_radius_all(int(PIP.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, r)
