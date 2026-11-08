class_name ItemThumb
extends Control
## A small picture of an item: a flyer on its own, or a mini room (rounded,
## flat, or with an ink outline) in a world's sky with its glow and spike rows,
## with an optional flyer, trail or exit portal (on the right wall) in it, or a
## music record. `open` leaves the room out (the trail, flyer and portal drawn
## straight on the live room: the Customize preview); `scenic` is the item
## popup's clean picture (the sky, a far hill, the flyer big with three puffs).
## Drawn from the world's own tokens, so new and paid worlds need no extra art.

const BORDER := 3.0
const CORNER := 10.0
const SPIKE_W := 14.0
const SPIKE_H := 9.0
const SCENIC_CORNER := 18.0
## The popup flyer's body on the 264 x 160 canvas (big: 64 px across).
const SCENIC_BODY := 64.0

var world: ThemeDef:
	set(value):
		world = value
		queue_redraw()
var flyer: Texture2D:
	set(value):
		flyer = value
		queue_redraw()
var trail: TrailStyle:
	set(value):
		trail = value
		queue_redraw()
var portal: PortalStyle:
	set(value):
		portal = value
		queue_redraw()
## A Customize music id (a track, Match my world or Shuffle owned): a record.
var music := "":
	set(value):
		music = value
		queue_redraw()
## Draws the picture faded (items the player can't afford yet).
var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()
## Just the flyer, no mini room.
var bare := false:
	set(value):
		bare = value
		queue_redraw()
## The ink outline round the mini room (the minimal kit's tiles go without).
var outlined := true:
	set(value):
		outlined = value
		queue_redraw()
## No mini room: the trail, flyer and portal on a clear background.
var open := false:
	set(value):
		open = value
		queue_redraw()
## The popup picture: the world's sky with a far hill and the flyer big.
var scenic := false:
	set(value):
		scenic = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(70, 70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	if world == null or size.x < 8.0 or size.y < 8.0:
		return
	var a := UiTokens.OPACITY_DISABLED if dimmed else 1.0
	var r := Rect2(Vector2.ZERO, size)
	if scenic:
		_draw_scenic(a)
		return
	if bare:
		if flyer != null:
			var s := minf(size.x, size.y)
			draw_texture_rect(
				flyer, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, a)
			)
		return
	if not open:
		_room(r.grow(-BORDER / 2.0), a)
	if portal != null:
		var door := portal.draw_thumb(self, r, world, a)
		if trail == null and flyer == null:
			_draw_approach(door, a)
	if not music.is_empty():
		_draw_music(r, a)
	var head := Vector2.ZERO
	if trail != null:
		head = _draw_trail(r, a, flyer == null)
	if flyer != null:
		var s := minf(size.x * 0.6, size.y * 0.5)
		var at := Vector2(size.x * 0.25, size.y * 0.38)
		if trail != null:
			# The flyer leads its trail (the loadout pictures).
			at = head - Vector2(s * 0.45, s * 0.55)
		draw_texture_rect(flyer, Rect2(at, Vector2(s, s)), false, Color(1, 1, 1, a))
	if outlined and not open:
		_outline(r.grow(-BORDER / 2.0), Color(UiTokens.INK_LINE, a))


## The popup picture (laid out on a 264 x 160 canvas, scaled to fit): the sky
## top to bottom in rounded corners, a far hill, three white puffs growing
## toward the flyer, and the flyer big.
func _draw_scenic(a: float) -> void:
	var r := Rect2(Vector2.ZERO, size)
	var frame := _rounded(r, SCENIC_CORNER)
	var cols := PackedColorArray()
	for p in frame:
		cols.append(Color(_sky_at(p.y / size.y), a))
	draw_polygon(frame, cols)
	var hill := PackedVector2Array()
	for i in 17:
		var x := size.x * i / 16.0
		var t := x / size.x
		hill.append(Vector2(x, size.y * (0.8 - 0.07 * sin(t * PI * 1.6 + 0.4))))
	hill.append(Vector2(size.x + 1.0, size.y + 1.0))
	hill.append(Vector2(-1.0, size.y + 1.0))
	for part in Geometry2D.intersect_polygons(hill, frame):
		draw_colored_polygon(part, Color(world.hill_far, a))
	var k := minf(size.x / 264.0, size.y / 160.0)
	var o := (size - Vector2(264.0, 160.0) * k) / 2.0
	for puff: Vector3 in [Vector3(70, 104, 4), Vector3(92, 96, 6), Vector3(114, 88, 8)]:
		var op := 0.3 + (puff.z - 4.0) * 0.0875
		draw_circle(o + Vector2(puff.x, puff.y) * k, puff.z * k, Color(1, 1, 1, op * a))
	if flyer != null:
		var s := SCENIC_BODY * BirdView.ART_CANVAS / 64.0 * k
		var c := o + Vector2(150, 76) * k
		draw_texture_rect(
			flyer, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, a)
		)


## The sky (mid stop at 55%), the glow and spike rows, in a rounded rectangle.
func _room(r: Rect2, a: float) -> void:
	var pts := _rounded(r, CORNER)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(Color(_sky_at((p.y - r.position.y) / r.size.y), a))
	draw_polygon(pts, cols)
	# The glow sits in the middle of the room, clear of the edges.
	var g := minf(r.size.x, r.size.y) * 0.26
	draw_circle(
		r.position + Vector2(r.size.x * 0.5, r.size.y * 0.42), g, Color(world.glow, 0.45 * a)
	)
	var spike := Color(world.spike, a)
	var n := maxi(int((r.size.x - CORNER) / SPIKE_W), 2)
	var w := (r.size.x - CORNER) / n
	var top := r.position.y + BORDER
	var bot := r.end.y - BORDER
	for i in n:
		var x := r.position.x + CORNER / 2.0 + i * w
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(x, top), Vector2(x + w, top), Vector2(x + w / 2.0, top + SPIKE_H)]
			),
			spike
		)
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(x, bot), Vector2(x + w, bot), Vector2(x + w / 2.0, bot - SPIKE_H)]
			),
			spike
		)


func _outline(r: Rect2, color: Color) -> void:
	var pts := _rounded(r, CORNER)
	pts.append(pts[0])
	draw_polyline(pts, color, BORDER, true)


static func _rounded(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# Keep the corners from meeting: touching arcs repeat a point, and a polygon
	# with repeated points can't be triangulated.
	radius = clampf(radius, 0.0, minf(r.size.x, r.size.y) / 2.0 - 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - radius, radius), -PI / 2.0],
		[r.end - Vector2(radius, radius), 0.0],
		[r.position + Vector2(radius, r.size.y - radius), PI / 2.0],
		[r.position + Vector2(radius, radius), PI],
	]
	for c: Array in corners:
		for k in 5:
			pts.append((c[0] as Vector2) + Vector2.from_angle(c[1] + PI / 2.0 * k / 4.0) * radius)
	return pts


func _sky_at(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.55:
		return world.sky_top.lerp(world.sky_mid, t / 0.55)
	return world.sky_mid.lerp(world.sky_bottom, (t - 0.55) / 0.45)


## A record (ink disc, grooves, a label in a world's accent) and two notes.
## Shuffle owned shows three records fanned out.
func _draw_music(r: Rect2, a: float) -> void:
	var s := minf(r.size.x, r.size.y)
	var c := r.position + Vector2(r.size.x * 0.45, r.size.y * 0.5)
	if music == MusicTrack.SHUFFLE:
		var tracks := Catalog.tracks()
		for i in 3:
			var t := tracks[i % tracks.size()]
			_record(c + Vector2((i - 1) * s * 0.16, (1 - i) * s * 0.04), s * 0.24, _label(t.id), a)
	else:
		_record(c, s * 0.3, _label(music), a)
	var white := Color(UiTokens.PANEL, a)
	_note(r.position + Vector2(r.size.x * 0.82, r.size.y * 0.36), s * 0.07, white)
	_note(r.position + Vector2(r.size.x * 0.76, r.size.y * 0.7), s * 0.05, Color(white, a * 0.7))


func _record(c: Vector2, rad: float, label: Color, a: float) -> void:
	draw_circle(c, rad, Color(UiTokens.INK_LINE, a))
	var groove := Color(UiTokens.PANEL, 0.18 * a)
	for f in [0.8, 0.62]:
		draw_arc(c, rad * f, 0.0, TAU, 32, groove, 1.0, true)
	draw_circle(c, rad * 0.36, Color(label, a))
	draw_circle(c, rad * 0.08, Color(UiTokens.PANEL, a))
	draw_arc(c, rad * 0.86, PI * 1.1, PI * 1.45, 10, Color(UiTokens.PANEL, 0.5 * a), 1.5, true)


## A note head with its stem.
func _note(at: Vector2, head: float, color: Color) -> void:
	draw_set_transform(at, -0.35, Vector2(1.3, 1.0))
	draw_circle(Vector2.ZERO, head, color)
	draw_set_transform(Vector2.ZERO)
	var top := at + Vector2(head * 1.1, -head * 3.6)
	draw_line(at + Vector2(head * 1.1, 0), top, color, maxf(head * 0.45, 1.0), true)


## The record label's colour: the accent of the first world a track fits
## (Match my world: the shown world's).
func _label(id: String) -> Color:
	var t := Catalog.track(id)
	if t != null and not t.worlds.is_empty():
		var w := Catalog.world(t.worlds[0])
		if w != null:
			return w.world_accent
	return world.world_accent


## The flyer's dot heading into the portal, with two fading dots behind it.
func _draw_approach(door: Vector2, a: float) -> void:
	var s := minf(size.x, size.y)
	for i in 3:
		var at := door + Vector2(-s * (0.3 + i * 0.13), s * 0.03 * i)
		draw_circle(at, s * (0.07 - i * 0.017), Color(UiTokens.PANEL, a * (1.0 - i * 0.32)))


## Draws the trail and returns its head. `dot` marks the head with a white
## dot when no flyer is drawn there.
func _draw_trail(r: Rect2, a: float, dot: bool = true) -> Vector2:
	var head := Color(world.trail, 0.85) if trail.use_world_color else trail.head_color
	var tail := Color(world.trail, 0.0) if trail.use_world_color else trail.tail_color
	var n := 6 if trail.kind == TrailStyle.Kind.STAMPS else 14
	var pts := PackedVector2Array()
	var ages := PackedFloat32Array()
	for i in n:
		var t := float(i) / (n - 1)
		pts.append(
			(
				r.position
				+ Vector2(
					lerpf(0.12, 0.7, t) * r.size.x, (0.75 - sin(t * PI * 0.8) * 0.4) * r.size.y
				)
			)
		)
		ages.append(trail.lifetime * (1.0 - t) * 0.9)
	TrailPainter.paint(self, pts, ages, trail, head, tail, minf(r.size.x, r.size.y) / 80.0, a)
	if dot:
		draw_circle(
			pts[n - 1] + Vector2(6, -2), minf(r.size.x, r.size.y) * 0.09, Color(UiTokens.PANEL, a)
		)
	return pts[n - 1]
