class_name ScrimBleed
extends Control
## Screens and overlays cover the room (ScreenLayout), but on taller phones the
## sky and ground carry on past it. A scrim gets one of these so its dim reaches
## the screen edges too: it paints the scrim's colour all around the scrim's
## rect, never over it, and never takes taps.

## Further than any phone reaches past the room (as RoomView.SURROUND).
const REACH := 2048.0

var _scrim: ColorRect


## Adds the bleed to `scrim` as an internal child, so the scrim's own children
## (and get_child indices) stay as they were.
static func attach(scrim: ColorRect) -> ScrimBleed:
	var bleed := ScrimBleed.new()
	bleed._scrim = scrim
	bleed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bleed.set_anchors_preset(Control.PRESET_FULL_RECT)
	bleed.show_behind_parent = true
	scrim.add_child(bleed, false, Node.INTERNAL_MODE_FRONT)
	return bleed


## The four rects around a scrim of `size`, in its own px.
static func rects(size: Vector2) -> Array[Rect2]:
	var r := REACH
	var out: Array[Rect2] = [
		Rect2(-r, -r, size.x + r * 2.0, r),
		Rect2(-r, size.y, size.x + r * 2.0, r),
		Rect2(-r, 0, r, size.y),
		Rect2(size.x, 0, r, size.y),
	]
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if _scrim == null:
		return
	for r in rects(size):
		draw_rect(r, _scrim.color)
