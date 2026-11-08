class_name WorldScenes
extends RefCounted
## One flat layered scene per world (design canvas "Worlds v4"), painted over
## the sky with a ScenePen. Worlds without their own scene get the generic one
## from their tokens. Every scene keeps the score area (SCORE_ZONE) clear and
## the middle of the room calm for play.

## Where the score sits; scenes keep sun, clouds and props out of it.
const SCORE_ZONE := Rect2(110, 90, 140, 95)
## Where spikes sit: ceiling and floor rows, and the wall slots on both sides.
## Everything a scene draws here keeps the spike at 3:1.
const SPIKE_ZONES := [
	Rect2(0, 0, 360, 34),
	Rect2(0, 606, 360, 34),
	Rect2(0, 62, 30, 516),
	Rect2(330, 62, 30, 516),
]
## Midnight Cage: a cool night blue over the scene, at most MIDNIGHT_MAX, less
## where the spikes would drop below MIDNIGHT_MIN_CONTRAST; the sky itself
## darkens further, up to MIDNIGHT_SKY_MAX.
const MIDNIGHT_TINT := Color("#182447")
const MIDNIGHT_MAX := 0.35
const MIDNIGHT_SKY_MAX := 0.5
const MIDNIGHT_MIN_CONTRAST := 3.05
const GENERIC := preload("res://game/run/scenes/worlds/generic.gd")
const PAINTERS := {
	"sunset": preload("res://game/run/scenes/worlds/sunset.gd"),
	"jungle": preload("res://game/run/scenes/worlds/jungle.gd"),
	"ice": preload("res://game/run/scenes/worlds/ice.gd"),
	"lava": preload("res://game/run/scenes/worlds/lava.gd"),
	"deepsea": preload("res://game/run/scenes/worlds/deepsea.gd"),
	"sugar": preload("res://game/run/scenes/worlds/sugar.gd"),
	"star": preload("res://game/run/scenes/worlds/star.gd"),
	"autumn": preload("res://game/run/scenes/worlds/autumn.gd"),
	"desert": preload("res://game/run/scenes/worlds/desert.gd"),
	"blossom": preload("res://game/run/scenes/worlds/blossom.gd"),
	"neon": preload("res://game/run/scenes/worlds/neon.gd"),
	"haunted": preload("res://game/run/scenes/worlds/haunted.gd"),
	"winterfest": preload("res://game/run/scenes/worlds/winterfest.gd"),
}

static var _midnight := {}


static func has_scene(world_id: String) -> bool:
	return PAINTERS.has(world_id)


## The sky (from the pen's current sky stops), then the world's scene.
static func paint(pen: ScenePen, t: ThemeDef) -> void:
	pen.paint_sky()
	var painter: GDScript = PAINTERS.get(t.id, GENERIC)
	painter.paint(pen, t)


static func in_spike_zone(rect: Rect2) -> bool:
	for z: Rect2 in SPIKE_ZONES:
		if rect.intersects(z):
			return true
	return false


## Every colour the world's scene shows behind its spikes, in every time of day
## (see-through shapes as they show over the sky).
static func colors_behind_spikes(t: ThemeDef) -> Array[Color]:
	var out: Array[Color] = []
	for room in t.palette_count():
		var pen := ScenePen.new(null, true)
		pen.sky = t.sky_for_room(room)
		pen.sky_split = t.sky_split
		paint(pen, t)
		for shape: Dictionary in pen.shapes:
			var rect: Rect2 = shape.rect
			var c: Color = shape.color
			if c.a < 0.02 or not in_spike_zone(rect):
				continue
			if c.a < 1.0:
				c = pen.sky_at(rect.get_center().y).lerp(Color(c, 1.0), c.a)
			if c not in out:
				out.append(c)
	return out


## How strongly Midnight Cage tints this world: x over the whole scene, y more
## on the sky alone. Each as dark as its maximum allows while the spike keeps
## MIDNIGHT_MIN_CONTRAST against everything behind it.
static func midnight_dim(t: ThemeDef) -> Vector2:
	var key := t.id + t.spike.to_html()
	if _midnight.has(key):
		return _midnight[key]
	var all := _darkest(t.spike, colors_behind_spikes(t), 0.0, MIDNIGHT_MAX)
	var sky := _darkest(t.spike, t.all_sky_stops(), all, MIDNIGHT_SKY_MAX)
	_midnight[key] = Vector2(all, sky)
	return _midnight[key]


## A colour of the sky or scene under the Midnight tint (sky_dim first, then dim).
static func midnight_color(c: Color, dim: float, sky_dim: float = 0.0) -> Color:
	return c.lerp(MIDNIGHT_TINT, sky_dim).lerp(MIDNIGHT_TINT, dim)


## The largest tint (in 0.01 steps, up to `most`) for colours that also get
## `under` from the overlay, keeping the spike readable on all of them.
static func _darkest(spike: Color, colors: Array[Color], under: float, most: float) -> float:
	var a := most
	while a > 0.0:
		var ok := true
		for c in colors:
			if Contrast.ratio(spike, midnight_color(c, under, a)) < MIDNIGHT_MIN_CONTRAST:
				ok = false
				break
		if ok:
			return a
		a = snappedf(a - 0.01, 0.01)
	return 0.0
