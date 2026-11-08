class_name FlyerArt
extends Control
## A flyer drawn straight on the room, with the short puff trail behind it
## (white dots growing toward the flyer), gently bobbing: the big flyer on
## Home and the "standing on the room" preview in Customize. Looks only.

## The flyer's body width in px (the art canvas is a bit bigger than the body).
@export var body := 52.0
@export var bob := true
@export var trail_dots := 4

var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## Bobs up and down this many px.
var bob_height := 5.0
var _time := 0.0


func _init(tex: Texture2D = null, body_px: float = 52.0) -> void:
	texture = tex
	body = body_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(body * 2.6, body * 1.4)


func _process(delta: float) -> void:
	if bob and is_visible_in_tree():
		_time += delta
		queue_redraw()


## The art square's side: the flyer art is 120 units with a ~64 unit body.
func art_size() -> float:
	return body * BirdView.ART_CANVAS / 64.0


func _draw() -> void:
	var y := size.y / 2.0 + (sin(_time * 2.4) * bob_height if bob else 0.0)
	var c := Vector2(size.x / 2.0 + body * 0.3, y)
	for i in trail_dots:
		var f := float(i + 1) / trail_dots
		var p := c + Vector2(-body * (1.55 - 0.32 * i), body * (0.45 - 0.1 * i))
		draw_circle(p, (2.5 + 6.0 * f) * body / 52.0, Color(1, 1, 1, 0.2 + 0.6 * f))
	if texture == null:
		return
	var s := art_size()
	draw_texture_rect(texture, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false)
