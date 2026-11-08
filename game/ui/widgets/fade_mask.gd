class_name FadeMask
extends Control
## Wraps a scroll list so its bottom edge fades out over FADE px instead of
## stopping in a hard line, which reads as cut off. The mask draws opaque
## white with a fading strip at the bottom; clip_children keeps only the
## children's pixels where the mask is opaque. Add `FadeMask.new(scroll)` in
## place of the scroll, and end the list with `FADE` of padding so its last
## row can scroll clear of the fade.

const FADE := 36.0


func _init(content: Control) -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = content.size_flags_horizontal
	size_flags_vertical = content.size_flags_vertical
	custom_minimum_size = content.custom_minimum_size
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	resized.connect(queue_redraw)


## The mask's alpha at a height in the box, for tests: 1 above the strip,
## falling to 0 at the bottom.
func alpha_at(y: float) -> float:
	var top := size.y - fade_height()
	if y <= top:
		return 1.0
	return clampf(1.0 - (y - top) / fade_height(), 0.0, 1.0)


## The strip is never more than half the box, so a short list stays readable.
func fade_height() -> float:
	return minf(FADE, size.y * 0.5)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := h - fade_height()
	draw_rect(Rect2(0, 0, w, top), Color.WHITE)
	var clear := Color(1, 1, 1, 0)
	draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color.WHITE, Color.WHITE, clear, clear])
	)
