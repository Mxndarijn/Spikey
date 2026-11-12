extends HazardPainter
## Pendulum (Lantern Swing): a safe chain of links from the ceiling and a
## deadly lantern in the spike colour with a warm glowing core. A twin lantern
## hangs from its own chain.

const PendulumHazard := preload("res://sim/hazards/pendulum.gd")

## Chain links per 20 px of chain (14 on the classic 280 px chain).
const LINK_PX := 20.0
## The bracket from the ceiling band down to the pivot: its rod and top plate.
const MOUNT_W := 4.0
const MOUNT_PLATE := 14.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as PendulumHazard
	var r := HazardLayer.px(h.radius)
	_lantern(c, HazardLayer.at(h.pivot_x, h.pivot_y), HazardLayer.at(h.x, h.y), r, look)
	if h.has_twin():
		_lantern(c, HazardLayer.at(h.twin_x, h.pivot_y), HazardLayer.at(h.x2, h.y2), r, look)


func _lantern(c: CanvasItem, pivot: Vector2, lamp: Vector2, r: float, look: HazardLook) -> void:
	var theme := look.theme
	var along := lamp - pivot
	var chain_end := pivot + along * (1.0 - (r * 0.9) / along.length())
	# Chain: safe, so it is drawn in the world accent, never the spike colour.
	var link_col := theme.world_accent
	var links := maxi(6, roundi(along.length() / LINK_PX))
	for i in links:
		var p := pivot.lerp(chain_end, (i + 0.5) / links)
		c.draw_circle(p, 2.4, link_col, false, 2.0, true)
	# The pivot hangs at the ceiling's kill line, among the spike tips: a short
	# bracket runs up into the ceiling band so the chain hangs from something.
	var mount := Color(theme.world_accent, 0.95)
	c.draw_rect(Rect2(pivot.x - MOUNT_W / 2.0, 0.0, MOUNT_W, pivot.y), mount)
	c.draw_rect(Rect2(pivot.x - MOUNT_PLATE / 2.0, 0.0, MOUNT_PLATE, RoomView.BAND + 3.0), mount)
	c.draw_circle(pivot, 4.5, mount, true, -1.0, true)
	c.draw_circle(pivot, 2.0, Color(theme.paper, 0.9), true, -1.0, true)
	# Lantern: cap, body, glowing window.
	var angle := along.angle() - PI / 2.0
	c.draw_set_transform(lamp, angle, Vector2.ONE)
	var body := PackedVector2Array(
		[
			Vector2(-r * 0.55, -r * 0.95),
			Vector2(r * 0.55, -r * 0.95),
			Vector2(r * 0.95, -r * 0.2),
			Vector2(r * 0.8, r * 0.75),
			Vector2(r * 0.35, r * 1.0),
			Vector2(-r * 0.35, r * 1.0),
			Vector2(-r * 0.8, r * 0.75),
			Vector2(-r * 0.95, -r * 0.2),
		]
	)
	c.draw_colored_polygon(body, theme.spike)
	body.append(body[0])
	c.draw_polyline(body, theme.spike_edge, 1.5, true)
	var flicker := 0.75 + sin(look.time * 11.0) * 0.1 + sin(look.time * 7.3) * 0.08
	c.draw_circle(Vector2(0, r * 0.05), r * 0.45, Color(theme.glow, flicker), true, -1.0, true)
	c.draw_circle(Vector2(0, r * 0.05), r * 0.22, Color(Color.WHITE, flicker), true, -1.0, true)
	c.draw_rect(Rect2(-r * 0.4, -r * 1.15, r * 0.8, r * 0.25), theme.spike_edge)
	c.draw_set_transform(Vector2.ZERO)
