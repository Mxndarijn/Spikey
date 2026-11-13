class_name BossBar
extends RefCounted
## What every boss painter draws besides the boss: under the score, the boss's
## name and its bar (one pip per bounce still to go, SimConfig.BOSS_POINTS in
## all); while the bird waits in the portal, the boss's title card. In the
## HUD's look: white in an ink halo (UiTheme.HUD_FILL, HUD_HALO) in every world,
## never the spike colour. Looks only.

const Boss := preload("res://sim/hazards/boss.gd")

const NAME_Y := 124.0
const PIPS_Y := 132.0
const PIP := Vector2(6.0, 10.0)
const PIP_GAP := 3.0
## The ink strip's margin around the pips.
const PIP_HALO := 2.0
const TITLE_Y := 410.0
## Steps the title card takes to fade after the hold.
const TITLE_FADE := 24.0


## A line of text in the HUD halo: the outline first, then the fill.
static func halo_text(
	c: CanvasItem, font: Font, pos: Vector2, text: String, size: int, halo: int, alpha := 1.0
) -> void:
	var edge := Color(UiTheme.HUD_HALO, alpha)
	var fill := Color(UiTheme.HUD_FILL, alpha)
	c.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, halo, edge)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


static func draw(c: CanvasItem, h: Boss, look: HazardLook) -> void:
	if look.sim == null:
		return
	var sim := look.sim
	var name := RoomInfo.name_of(sim.room.def.id)
	var font := GameFonts.ui(800)
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var tag := name.to_upper()
	var size := UiTokens.FONT_SIZE_TAG
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	# Under the score, which a practice or replay banner pushes down.
	var dy := look.score_top - HazardLook.RUN_SCORE_TOP
	halo_text(c, font, Vector2((w - tw) / 2.0, NAME_Y + dy), tag, size, UiTheme.HALO_SMALL)
	var left := clampi(sim.next_exit_score() - sim.state.score, 0, SimConfig.BOSS_POINTS)
	if h.down_at >= 0:
		left = 0
	var n := SimConfig.BOSS_POINTS
	var x0 := (w - (n * (PIP.x + PIP_GAP) - PIP_GAP)) / 2.0
	# One ink strip behind all pips is their halo; spent pips stay dim on it.
	var strip := Rect2(x0, PIPS_Y + dy, n * (PIP.x + PIP_GAP) - PIP_GAP, PIP.y).grow(PIP_HALO)
	UiTheme.flat(UiTheme.HUD_HALO, 3, 0).draw(c.get_canvas_item(), strip)
	for i in n:
		var r := Rect2(x0 + i * (PIP.x + PIP_GAP), PIPS_Y + dy, PIP.x, PIP.y)
		var on := i < left
		var fill := UiTheme.HUD_FILL if on else Color(UiTheme.HUD_FILL, 0.22)
		UiTheme.flat(fill, 2, 0).draw(c.get_canvas_item(), r)
	_title(c, h, look, name)


## The title card over the waiting room: "BOSS · 100", the name, a line.
static func _title(c: CanvasItem, h: Boss, look: HazardLook, name: String) -> void:
	var sim := look.sim
	var a := 1.0
	if sim.state.arrival_hold <= 0 or h.t > 0:
		a = 1.0 - h.t / TITLE_FADE
	if a <= 0.0 or sim.room.points > 0:
		return
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var tag := "BOSS · %d" % sim.room.entry_score
	var small := GameFonts.ui(800)
	var tw := small.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.FONT_SIZE_TAG).x
	var pill := Rect2((w - tw) / 2.0 - 9.0, TITLE_Y - 18.0, tw + 18.0, 20.0)
	UiTheme.flat(Color(UiTheme.HUD_HALO, a), UiTokens.RADIUS_S, 0).draw(c.get_canvas_item(), pill)
	var on_pill := Color(UiTheme.HUD_FILL, a)
	c.draw_string(
		small,
		Vector2(pill.position.x + 9.0, TITLE_Y - 4.0),
		tag,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTokens.FONT_SIZE_TAG,
		on_pill
	)
	var big := GameFonts.display()
	var size := UiTokens.FONT_SIZE_TITLE_XL
	var nw := big.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if nw > w - 40.0:
		size = int(size * (w - 40.0) / nw)
		nw = big.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	halo_text(c, big, Vector2((w - nw) / 2.0, TITLE_Y + 40.0), name, size, UiTheme.HALO_BIG, a)
	var line := "Break it in %d bounces" % SimConfig.BOSS_POINTS
	var lf := GameFonts.ui(700)
	var lw := lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.FONT_SIZE_LABEL).x
	var at := Vector2((w - lw) / 2.0, TITLE_Y + 68.0)
	halo_text(c, lf, at, line, UiTokens.FONT_SIZE_LABEL, UiTheme.HALO_SMALL, a)


## A two-tone rounded tooth: `base` is the middle of its base, `dir` points to
## the tip, `depth` px away.
static func tooth(
	c: CanvasItem, base: Vector2, dir: Vector2, half: float, depth: float, theme: ThemeDef
) -> void:
	var side := Vector2(-dir.y, dir.x)
	var a := base + side * half
	var b := base - side * half
	var tip := base + dir * depth
	c.draw_colored_polygon(PackedVector2Array([a, tip, b]), theme.spike)
	c.draw_colored_polygon(PackedVector2Array([base, tip, b]), theme.spike_edge)


## Seconds since the boss broke (0 before).
static func down_time(h: Boss) -> float:
	if h.down_at < 0:
		return 0.0
	return (h.t - h.down_at) / float(SimConfig.TICKS_PER_SECOND)
