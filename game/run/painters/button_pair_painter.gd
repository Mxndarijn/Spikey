extends HazardPainter
## Buttons: a cap set into the ceiling row and one into the floor row. The
## lit one (the next to press) is filled in the world accent with two
## chevrons pointing at it from the room; the other is paper, dimmed. A press
## dips the cap and throws a few flat shards; pressing the unlit one only
## dents it. The cap covers the edge spikes where it sits: there the edge is
## safe. Never in the spike colour.

const ButtonPairHazard := preload("res://sim/hazards/button_pair.gd")
## Deep enough to cover the edge spikes (band and tips) under the cap.
const CAP := 40.0
const DIP := 6.0
const DENT := 2.0
const PRESS_FX := 18.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as ButtonPairHazard
	for top: bool in [true, false]:
		_cap(c, h, look, top)


func _cap(c: CanvasItem, h: ButtonPairHazard, look: HazardLook, top: bool) -> void:
	var theme := look.theme
	var x0 := HazardLayer.px(h.x0(top))
	var x1 := HazardLayer.px(h.x1(top))
	var lit := h.lit_top == top and not _exit_open(look)
	var dip := 0.0
	if h.last_top == top:
		dip = DIP * clampf(1.0 - h.since_press / 10.0, 0.0, 1.0)
		dip = maxf(dip, DENT * clampf(1.0 - h.since_wrong / 10.0, 0.0, 1.0))
	var depth := CAP + dip
	var y := 0.0 if top else RoomView.H - depth
	var rect := Rect2(x0, y, x1 - x0, depth)
	# An opaque backing hides the edge spikes under the cap.
	var back := StyleBoxFlat.new()
	back.bg_color = theme.paper
	_round(back, top, 12)
	back.draw(c.get_canvas_item(), rect)
	var cap := StyleBoxFlat.new()
	cap.bg_color = theme.world_accent if lit else Color(theme.ink, 0.12)
	_round(cap, top, 12)
	cap.draw(c.get_canvas_item(), rect)
	# A light strip on the cap's face.
	var mid := (x0 + x1) / 2.0
	var face_y := depth - 10.0 if top else RoomView.H - depth + 5.0
	c.draw_rect(Rect2(mid - 16.0, face_y, 32.0, 5.0), Color(theme.paper, 0.6))
	var dir := 1.0 if top else -1.0
	var edge := depth if top else RoomView.H - depth
	if lit:
		var pulse := 0.5 + 0.5 * sin(look.time * 5.0)
		for i in 2:
			var cy := edge + dir * (20.0 + i * 18.0)
			var a := (1.0 if i == 0 else 0.5) * (0.7 + 0.3 * pulse)
			var pts := PackedVector2Array(
				[
					Vector2(mid - 12.0, cy + dir * 12.0),
					Vector2(mid, cy),
					Vector2(mid + 12.0, cy + dir * 12.0)
				]
			)
			c.draw_polyline(pts, Color(theme.world_accent, a), 5.0, true)
	if h.last_top == top and h.since_press < PRESS_FX:
		var k := h.since_press / PRESS_FX
		for i in 5:
			var ang := PI * (0.15 + 0.175 * i)
			var r := 14.0 + 26.0 * k
			var p := Vector2(mid + cos(ang) * r * 1.4, edge + dir * sin(ang) * r)
			var tri := PackedVector2Array(
				[p + Vector2(0, -4), p + Vector2(4, 3), p + Vector2(-4, 3)]
			)
			c.draw_colored_polygon(tri, Color(theme.world_accent, 1.0 - k))


## Floor spikes wholly under the bottom button are gone: the edge is safe there.
func floor_sink(hazard: Hazard, left: float, right: float) -> float:
	var h := hazard as ButtonPairHazard
	var x0 := HazardLayer.px(h.x0(false))
	var x1 := HazardLayer.px(h.x1(false))
	return 1.0 if left >= x0 and right <= x1 else 0.0


static func _round(box: StyleBoxFlat, top: bool, r: int) -> void:
	box.anti_aliasing = true
	if top:
		box.corner_radius_bottom_left = r
		box.corner_radius_bottom_right = r
	else:
		box.corner_radius_top_left = r
		box.corner_radius_top_right = r


## With the exit open both buttons go dark.
static func _exit_open(look: HazardLook) -> bool:
	return look.sim != null and look.sim.state.exit_open
