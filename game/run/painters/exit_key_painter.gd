extends HazardPainter
## Locked Out: gold keys bobbing in the room, a key counter at the top middle
## (under the score) and a padlock on each open exit while it is locked. The
## padlock shows a pip per key (gold once taken) and a ring with one segment
## per locked bounce left before the lock gives up. Safe things only, so coin
## colours, paper and ink, never the spike colour.

const ExitKeyHazard := preload("res://sim/hazards/exit_key.gd")

const LOCK_INSET := 46.0
const LOCK_SCALE := 1.35
const RING_R := 24.0
## The key counter: centre height (under the HUD score), slot width, height.
const COUNTER_Y := 128.0
const SLOT_W := 34.0
const COUNTER_H := 36.0
const COUNTER_FONT := 16
## The counter pill's ink rim, px.
const RIM := 2.0
## A chain key pops in over this many seconds (sim steps / 60).
const POP_STEPS := 18
const MISSING := Color(0.137255, 0.101961, 0.200000, 0.28)
const RING_USED := Color(0.137255, 0.101961, 0.200000, 0.18)


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as ExitKeyHazard
	var bob := sin(look.time * 4.0) * 3.0
	for i in h.count:
		if not h.shown(i):
			continue
		var grow := 1.0
		if h.mode == ExitKeyHazard.Mode.CHAIN and i > 0:
			grow = clampf(float(h.t - h.born[i]) / POP_STEPS, 0.0, 1.0)
		var p := HazardLayer.at(h.kx[i], h.ky[i]) + Vector2(0, bob if i % 2 == 0 else -bob)
		_key(c, p, 0.4 + 0.6 * grow, UiTokens.COIN, UiTokens.COIN_EDGE)
	# Under the HUD score, which a practice or replay banner pushes down.
	_counter(c, h, COUNTER_Y + look.score_top - HazardLook.RUN_SCORE_TOP)
	if h.door_open and h.locked():
		var x := LOCK_INSET if h.door_side == 0 else RoomView.W - LOCK_INSET
		_lock(c, Vector2(x, HazardLayer.px(h.door_a_y)), h)
		if h.door_b_y != 0:
			_lock(c, Vector2(x, HazardLayer.px(h.door_b_y)), h)


func _key(c: CanvasItem, p: Vector2, sc: float, fill: Color, edge: Color) -> void:
	c.draw_set_transform(p, -0.5, Vector2(sc, sc))
	c.draw_arc(Vector2(-9, 0), 7.0, 0.0, TAU, 20, edge, 5.0, true)
	c.draw_rect(Rect2(-3, -3, 20, 6), fill)
	c.draw_rect(Rect2(10, 3, 4, 6), fill)
	c.draw_rect(Rect2(15, 3, 3, 4), fill)
	c.draw_set_transform(Vector2.ZERO)


## A cream pill with one slot per key: grey while missing, gold once taken,
## then the count. With every key the pill turns mint. An ink-900 rim (the
## HUD's halo colour) keeps it apart from a light sky.
func _counter(c: CanvasItem, h: ExitKeyHazard, cy: float) -> void:
	var w := h.count * SLOT_W + 52.0
	var rect := Rect2(RoomView.W / 2.0 - w / 2.0, cy - COUNTER_H / 2.0, w, COUNTER_H)
	var fill := UiTokens.SUCCESS if h.done() else UiTokens.PANEL
	UiTheme.flat(UiTheme.HUD_HALO, UiTokens.RADIUS_PILL, 0).draw(
		c.get_canvas_item(), rect.grow(RIM)
	)
	UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0).draw(c.get_canvas_item(), rect)
	for i in h.count:
		var p := Vector2(rect.position.x + 22.0 + i * SLOT_W, cy)
		if i < h.got:
			_key(c, p, 0.85, UiTokens.COIN, UiTokens.COIN_EDGE)
		else:
			_key(c, p, 0.85, MISSING, MISSING)
	var text := "%d/%d" % [h.got, h.count]
	c.draw_string(
		GameFonts.wide(900, 100),
		Vector2(rect.end.x - 40.0, cy + COUNTER_FONT * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		36.0,
		COUNTER_FONT,
		UiTokens.ON_PANEL
	)


func _lock(c: CanvasItem, p: Vector2, h: ExitKeyHazard) -> void:
	c.draw_set_transform(p, 0.0, Vector2(LOCK_SCALE, LOCK_SCALE))
	var segs := ExitKeyHazard.MAX_LOCKED_BOUNCES
	var left := segs - h.locked_bounces
	var step := TAU / segs
	for i in segs:
		var a0 := -PI / 2.0 + i * step + 0.12
		var col := UiTokens.INK_LINE if i < left else RING_USED
		c.draw_arc(Vector2(0, 1), RING_R, a0, a0 + step - 0.24, 6, col, 4.0, true)
	c.draw_arc(Vector2(0, -6), 7.0, PI, TAU, 12, UiTokens.INK_LINE, 4.0, true)
	c.draw_rect(Rect2(-10, -6, 20, 16), UiTokens.PANEL)
	if h.count > 1:
		for i in h.count:
			var col := UiTokens.COIN_EDGE if i < h.got else MISSING
			c.draw_circle(Vector2(-(h.count - 1) * 2.75 + i * 5.5, 2), 2.2, col)
	else:
		c.draw_rect(Rect2(-2, -1, 4, 7), UiTokens.INK_LINE)
	c.draw_set_transform(Vector2.ZERO)
