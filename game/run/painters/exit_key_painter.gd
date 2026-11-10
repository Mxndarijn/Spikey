extends HazardPainter
## Locked Exit: a gold key (two in the Two keys variant) bobbing in the room,
## and a padlock on each open exit while it is locked. Safe things only, so
## coin colours and paper, never the spike colour.

const ExitKeyHazard := preload("res://sim/hazards/exit_key.gd")

const LOCK_INSET := 26.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as ExitKeyHazard
	if not h.taken:
		var bob := sin(look.time * 4.0) * 3.0
		_key(c, HazardLayer.at(h.x0, h.y0) + Vector2(0, bob))
		if h.mode == ExitKeyHazard.Mode.TWO:
			_key(c, HazardLayer.at(h.x1, h.y1) + Vector2(0, -bob))
	if h.door_open and h.locked():
		var x := LOCK_INSET if h.door_side == 0 else RoomView.W - LOCK_INSET
		_lock(c, Vector2(x, HazardLayer.px(h.door_a_y)))
		if h.door_b_y != 0:
			_lock(c, Vector2(x, HazardLayer.px(h.door_b_y)))


func _key(c: CanvasItem, p: Vector2) -> void:
	c.draw_set_transform(p, -0.5)
	c.draw_arc(Vector2(-9, 0), 7.0, 0.0, TAU, 20, UiTokens.COIN_EDGE, 5.0, true)
	c.draw_rect(Rect2(-3, -3, 20, 6), UiTokens.COIN)
	c.draw_rect(Rect2(10, 3, 4, 6), UiTokens.COIN)
	c.draw_rect(Rect2(15, 3, 3, 4), UiTokens.COIN)
	c.draw_set_transform(Vector2.ZERO)


func _lock(c: CanvasItem, p: Vector2) -> void:
	c.draw_arc(p + Vector2(0, -6), 8.0, PI, TAU, 12, UiTokens.INK_LINE, 4.0, true)
	c.draw_rect(Rect2(p + Vector2(-11, -6), Vector2(22, 18)), UiTokens.PANEL)
	c.draw_rect(Rect2(p + Vector2(-2, 0), Vector2(4, 7)), UiTokens.INK_LINE)
