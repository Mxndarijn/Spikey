class_name TrailStyle
extends Resource
## How a bird's trail looks. Cosmetic only: players will unlock or buy trails
## in the shop (see docs/ARCHITECTURE.md). Each shop trail becomes a .tres
## file in data/trails/ built from this class.

enum Kind { RIBBON, DOTS }

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


## The free default: a ribbon in the current world's trail color.
static func world_ribbon() -> TrailStyle:
	var t := TrailStyle.new()
	t.use_world_color = true
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
