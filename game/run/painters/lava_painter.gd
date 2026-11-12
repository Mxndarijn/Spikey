extends HazardPainter
## Lava Rise: the lava in the spike colour, the one colour that kills, with a
## lighter crest. What sinks it is safe, so it is paper with a mint frost mark:
## the cool stone, the Cold Wall's ice block in its wall slot (with a mint
## glow), and the rafts of cooled rock riding the wave (they float up out of
## the lava over their first second).

const LavaHazard := preload("res://sim/hazards/lava.gd")

const WAVE := 3.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as LavaHazard
	var theme := look.theme
	var line := HazardLayer.px(h.line)
	var w := RoomView.W
	if h.line < SimConfig.KILL_BOTTOM:
		for i in LavaHazard.MAX_RAFTS:
			if h.raft_on[i] and h.raft_age[i] < LavaHazard.RAFT_RISE:
				_raft(c, h, i, line, look)
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w:
			pts.append(Vector2(x, _wave(x, line, look)))
			x += 8.0
		pts.append(Vector2(w, RoomView.H + RoomView.SURROUND))
		pts.append(Vector2(0, RoomView.H + RoomView.SURROUND))
		c.draw_colored_polygon(pts, theme.spike)
		for i in range(0, int(w), 30):
			var cy := _wave(i + 10.0, line, look) - 1.0
			c.draw_set_transform(Vector2(i + 10.0, cy), 0.0, Vector2(1.0, 0.35))
			c.draw_circle(Vector2.ZERO, 9.0, theme.spike_edge)
			c.draw_set_transform(Vector2.ZERO)
	for i in LavaHazard.MAX_RAFTS:
		if h.raft_on[i] and h.raft_age[i] >= LavaHazard.RAFT_RISE:
			_raft(c, h, i, line, look)
	if h.ice_on:
		_ice(c, h, look)
	if h.stone_on:
		var p := HazardLayer.at(h.stone_x, h.stone_y)
		c.draw_set_transform(p, 0.2, Vector2(1.0, 0.8))
		c.draw_circle(Vector2.ZERO, 15.0, UiTokens.PANEL)
		c.draw_set_transform(Vector2.ZERO)
		_frost(c, p, 7.0, look)


func _wave(x: float, line: float, look: HazardLook) -> float:
	return line + sin(x / 22.0 + look.time * 4.0) * WAVE


func _frost(c: CanvasItem, p: Vector2, r: float, look: HazardLook) -> void:
	for k in 3:
		var a := k * PI / 3.0 + look.time
		var d := Vector2(cos(a), sin(a)) * r
		c.draw_line(p - d, p + d, UiTokens.SUCCESS, 3.0, true)


## A raft slab on the wave. Rising, it comes up from below the surface (drawn
## before the lava, so the lava covers what is still under).
func _raft(c: CanvasItem, h: LavaHazard, i: int, line: float, look: HazardLook) -> void:
	var x := HazardLayer.px(h.raft_x[i])
	var half := HazardLayer.px(LavaHazard.RAFT_HALF)
	var high := HazardLayer.px(LavaHazard.RAFT_HIGH)
	var rise := clampf(float(h.raft_age[i]) / LavaHazard.RAFT_RISE, 0.0, 1.0)
	var top := _wave(x, line, look) - high + (1.0 - rise) * 18.0
	var rect := Rect2(x - half, top, half * 2.0, high + 8.0)
	c.draw_rect(rect, UiTokens.PANEL)
	var crack := UiTokens.PANEL.lerp(look.theme.spike_edge, 0.45)
	c.draw_line(Vector2(x - 14.0, top + 2.0), Vector2(x - 8.0, top + high + 4.0), crack, 2.0, true)
	c.draw_line(Vector2(x + 10.0, top + 2.0), Vector2(x + 4.0, top + high), crack, 2.0, true)
	if rise >= 1.0:
		_frost(c, Vector2(x + half - 12.0, top + 7.0), 4.0, look)


## The ice block in its wall slot, over a mint glow.
func _ice(c: CanvasItem, h: LavaHazard, look: HazardLook) -> void:
	var depth := HazardLayer.px(LavaHazard.ICE_DEPTH)
	var cy := HazardLayer.px(SimConfig.slot_center_y(h.ice_slot))
	var half := HazardLayer.px(SimConfig.SLOT_SIZE) / 2.0
	var x0 := 0.0 if h.ice_side == 0 else RoomView.W - depth - 6.0
	var glow := Color(UiTokens.SUCCESS, 0.35)
	c.draw_rect(Rect2(x0 - 4.0, cy - half - 4.0, depth + 14.0, half * 2.0 + 8.0), glow)
	c.draw_rect(Rect2(x0, cy - half + 1.0, depth + 6.0, half * 2.0 - 2.0), UiTokens.PANEL)
	_frost(c, Vector2(x0 + (depth + 6.0) / 2.0, cy), 6.0, look)
