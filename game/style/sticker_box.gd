class_name StickerBox
extends StyleBox
## A Sticker Pop sticker: a hard ink drop (no blur) under a filled face with an
## ink outline. StyleBoxFlat can't do this: its shadow only draws blurred.
## `shift` moves the face into its drop (pressed buttons).

var face := StyleBoxFlat.new()
var drop := StyleBoxFlat.new()
var drop_offset := Vector2(4, 4)
var shift := Vector2.ZERO


## fill, corner radius, outline width, drop offset; padding is the content margin.
static func make(
	fill: Color,
	radius: int,
	border: int = 3,
	drop_by: Vector2 = Vector2(4, 4),
	padding: int = UiTokens.SPACE_3,
	border_color: Color = UiTokens.INK_LINE
) -> StickerBox:
	var s := StickerBox.new()
	s.face.bg_color = fill
	s.face.set_corner_radius_all(radius)
	s.face.set_border_width_all(border)
	s.face.border_color = border_color
	s.face.anti_aliasing = true
	s.drop.bg_color = UiTokens.INK_LINE
	s.drop.set_corner_radius_all(radius)
	s.drop.anti_aliasing = true
	s.drop_offset = drop_by
	s.set_content_margin_all(padding)
	return s


## A copy for the pressed state: the face sinks `by` px into its drop.
func pressed(by: float = 3.0) -> StickerBox:
	var s := copy()
	var d := drop_offset
	s.shift = Vector2(signf(d.x) * minf(by, absf(d.x)), signf(d.y) * minf(by, absf(d.y)))
	return s


func copy() -> StickerBox:
	var s := StickerBox.new()
	s.face = face.duplicate() as StyleBoxFlat
	s.drop = drop.duplicate() as StyleBoxFlat
	s.drop_offset = drop_offset
	s.shift = shift
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_content_margin(side, get_content_margin(side))
	return s


func with_fill(fill: Color) -> StickerBox:
	var s := copy()
	s.face.bg_color = fill
	return s


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if drop_offset != Vector2.ZERO:
		drop.draw(to_canvas_item, Rect2(rect.position + drop_offset, rect.size))
	face.draw(to_canvas_item, Rect2(rect.position + shift, rect.size))
