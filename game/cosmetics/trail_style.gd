class_name TrailStyle
extends Resource
## How a bird's trail looks. Cosmetic only: players will unlock or buy trails
## in the shop (see docs/ARCHITECTURE.md). Each shop trail becomes a .tres
## file in data/trails/ built from this class.

## RIBBON: one fading band. DOTS: shrinking circles. STRIPES: parallel bands in
## `colors`. COMET: a glowing ribbon with sparks. STAMPS: little `shape`s left
## behind that drift, spin and grow as they fade.
enum Kind { RIBBON, DOTS, STRIPES, COMET, STAMPS }
enum Shape { BUBBLE, CONFETTI, SPARKLE, LEAF, NOTE, PIXEL }

@export var id := "world_ribbon"
@export var display_name := "World Ribbon"
@export var kind: Kind = Kind.RIBBON
## Seconds a point stays in the trail.
@export var lifetime := 0.28
@export var width := 18.0
@export var head_color := Color("#FFFFFFD9")
@export var tail_color := Color("#FFD0E800")
## Minimum distance between stored points, in pixels.
@export var spacing := 3.0
## Take the colors from the world's trail token instead of head/tail_color
## (the free default trail; shop trails bring their own colors).
@export var use_world_color := false
## Color for the trail's picture in the shop.
@export var preview_color := Color("#FFE3A3")
## Bands (STRIPES), or the palette stamps and sparks cycle through.
@export var colors := PackedColorArray()
@export var shape: Shape = Shape.BUBBLE
## Stamp size at the end of its life, relative to its start.
@export var grow := 1.0
## Stamp drift in px/s while fading: positive rises, negative falls.
@export var rise := 0.0
## Stamp spin in radians per second.
@export var spin := 0.0
## Leave a stamp on every flap instead of every `spacing` pixels.
@export var stamp_on_flap := false
## How much a band narrows toward its tail: 1 tapers to a point, 0 keeps its
## full width and only fades (RIBBON, STRIPES, COMET).
@export var taper := 1.0


## The free default: a ribbon in the current world's trail color.
static func world_ribbon() -> TrailStyle:
	var t := TrailStyle.new()
	t.use_world_color = true
	t.preview_color = Color("#FFFFFF")
	return t


static func spark_dots() -> TrailStyle:
	var t := TrailStyle.new()
	t.id = "spark_dots"
	t.display_name = "Spark Dots"
	t.kind = Kind.DOTS
	t.lifetime = 0.35
	t.width = 9.0
	t.head_color = Color("#FFE3A3")
	t.tail_color = Color("#FF8A5B00")
	t.spacing = 9.0
	return t


static func rainbow_ribbon() -> TrailStyle:
	var t := TrailStyle.new()
	t.id = "rainbow_ribbon"
	t.display_name = "Rainbow Ribbon"
	t.kind = Kind.STRIPES
	t.width = 24.0
	t.lifetime = 0.4
	t.taper = 0.0
	t.colors = PackedColorArray(
		[
			Color("#FF5E7A"),
			Color("#FFB020"),
			Color("#FFE45C"),
			Color("#3FD9A3"),
			Color("#5CC8FF"),
			Color("#8A6AD0"),
		]
	)
	t.preview_color = Color("#FFE45C")
	return t


static func bubble_stream() -> TrailStyle:
	var t := _stamps("bubble_stream", "Bubble Stream", Shape.BUBBLE, [Color("#FFFFFF")])
	t.width = 6.0
	t.lifetime = 0.7
	t.spacing = 24.0
	t.grow = 3.3
	t.rise = 22.0
	return t


static func comet_tail() -> TrailStyle:
	var t := TrailStyle.new()
	t.id = "comet_tail"
	t.display_name = "Comet Tail"
	t.kind = Kind.COMET
	t.width = 11.0
	t.lifetime = 0.4
	t.taper = 0.35
	t.head_color = Color("#FFD27A")
	t.tail_color = Color("#FF943300")
	# Halo #FF9433, not the board's #FF8A2A: that is Haunted Moon's spike colour.
	t.colors = PackedColorArray([Color("#FF9433"), Color("#FFF4CF"), Color("#FFB347")])
	t.preview_color = Color("#FFD27A")
	return t


static func confetti() -> TrailStyle:
	var t := _stamps(
		"confetti",
		"Confetti",
		Shape.CONFETTI,
		[Color("#FF5E7A"), Color("#5CC8FF"), Color("#FFE45C"), Color("#FFFFFF"), Color("#8A6AD0")]
	)
	t.width = 9.0
	t.lifetime = 0.6
	t.spacing = 15.0
	t.rise = -30.0
	t.spin = 8.0
	return t


static func star_dust() -> TrailStyle:
	var t := _stamps("star_dust", "Star Dust", Shape.SPARKLE, [Color("#FFF4CF")])
	t.width = 16.0
	t.lifetime = 0.55
	t.spacing = 24.0
	return t


static func leaf_swirl() -> TrailStyle:
	var t := _stamps(
		"leaf_swirl",
		"Leaf Swirl",
		Shape.LEAF,
		[Color("#7BBF3E"), Color("#E8A21A"), Color("#FF7A3D")]
	)
	t.width = 10.0
	t.lifetime = 0.7
	t.spacing = 24.0
	t.grow = 1.6
	t.rise = -26.0
	t.spin = 3.0
	return t


static func music_notes() -> TrailStyle:
	var t := _stamps("music_notes", "Music Notes", Shape.NOTE, [Color("#FFFFFF")])
	t.width = 12.0
	t.lifetime = 0.8
	t.rise = 30.0
	t.stamp_on_flap = true
	return t


static func pixel_trail() -> TrailStyle:
	var t := _stamps(
		"pixel_trail", "Pixel Trail", Shape.PIXEL, [Color("#00E5FF"), Color("#7DF9FF")]
	)
	t.width = 8.0
	t.lifetime = 0.55
	t.spacing = 14.0
	t.grow = 0.75
	return t


static func _stamps(p_id: String, p_name: String, p_shape: Shape, palette: Array) -> TrailStyle:
	var t := TrailStyle.new()
	t.id = p_id
	t.display_name = p_name
	t.kind = Kind.STAMPS
	t.shape = p_shape
	t.colors = PackedColorArray(palette)
	t.preview_color = palette[0]
	return t
