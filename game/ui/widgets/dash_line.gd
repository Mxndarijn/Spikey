class_name DashLine
extends Control
## A dashed ink line across its middle, 2px thick (the daily board's prize cut-off).

const DASH := 6.0
const WIDTH := 2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y := size.y / 2.0
	draw_dashed_line(Vector2(0, y), Vector2(size.x, y), UiTokens.ON_SKY, WIDTH, DASH)
