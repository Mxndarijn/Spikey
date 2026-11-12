extends HazardPainter
## Crowded (Filling up): the wall behind the bird has no spikes out, but its
## crowd keeps its seats. Each seat shows as a small tab in the safe guide
## ink (not the spike colour: nothing there kills now), and the newcomers walk
## in along that wall from its nearer corner to the seat they picked. When the
## bird turns for that wall, its spikes come out of those seats.

const CrowdFillHazard := preload("res://sim/hazards/crowd_fill.gd")
## Steps a newcomer takes to walk to its seat.
const WALK := 40.0
const TAB_W := 6.0
const TAB_H := 24.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CrowdFillHazard
	if look.sim == null:
		return
	var seat_col := HazardLayer.guide(look.theme)
	var walk_col := Color(look.theme.ink, 0.45)
	for side in 2:
		# Only the wall behind the bird: the wall ahead shows its spikes.
		if look.sim.wall_mask(side) != 0:
			continue
		var x := HazardLayer.px(
			look.sim.room.wall_left() if side == 0 else look.sim.room.wall_right()
		)
		var tab_x := x if side == 0 else x - TAB_W
		var seated := h.seats(side)
		var coming := h.coming(side)
		var k := clampf(h.since_pick / WALK, 0.0, 1.0)
		for slot in SimConfig.SLOT_COUNT:
			var y := HazardLayer.px(SimConfig.slot_center_y(slot))
			if RoomRules.has_slot(seated, slot):
				_tab(c, tab_x, y, seat_col)
			elif RoomRules.has_slot(coming, slot):
				# From the nearer corner of the wall to the seat.
				var from_y := HazardLayer.px(SimConfig.SLOT_TOP)
				if slot >= SimConfig.SLOT_COUNT / 2:
					from_y = HazardLayer.px(
						SimConfig.SLOT_TOP + SimConfig.SLOT_COUNT * SimConfig.SLOT_SIZE
					)
				_tab(c, tab_x, lerpf(from_y, y, k), walk_col)


static func _tab(c: CanvasItem, x: float, y: float, col: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.set_corner_radius_all(3)
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), Rect2(x, y - TAB_H / 2.0, TAB_W, TAB_H))
