extends HazardPainter
## Spike Belt: a rail along each side wall with tread marks that move with the
## spikes, and chevrons showing which way each belt runs. The spikes themselves
## are drawn by RoomView, shifted by GameSim.wall_shift.

const BeltHazard := preload("res://sim/hazards/belt.gd")

const RAIL_W := 6.0
const TREAD := 20.0
const TREAD_H := 4.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BeltHazard
	var top := HazardLayer.px(SimConfig.SLOT_TOP)
	var span := HazardLayer.px(SimConfig.SLOT_COUNT * SimConfig.SLOT_SIZE)
	var edge := look.theme.spike_edge
	for side in 2:
		var x := 0.0 if side == 0 else RoomView.W - RAIL_W
		var shift := HazardLayer.px(h.left_shift if side == 0 else h.right_shift)
		c.draw_rect(Rect2(x, top, RAIL_W, span), Color(edge, 0.35))
		var k := 0.0
		while k < span:
			var y := top + fposmod(k + shift, span)
			c.draw_rect(Rect2(x, y, RAIL_W, TREAD_H), Color(edge, 0.8))
			k += TREAD
		var dir := float(h.left_dir if side == 0 else h.right_dir)
		var cx := 50.0 if side == 0 else RoomView.W - 50.0
		var cy := top + span / 2.0
		for i in 3:
			var y := cy + (i - 1) * 18.0 + dir * fposmod(look.time * 12.0, 18.0)
			var pts := PackedVector2Array(
				[
					Vector2(cx - 7.0, y - dir * 4.0),
					Vector2(cx, y + dir * 3.0),
					Vector2(cx + 7.0, y - dir * 4.0)
				]
			)
			c.draw_polyline(pts, Color(look.theme.glow, 0.35), 3.0, true)
