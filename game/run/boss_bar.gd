class_name BossBar
extends RefCounted
## What every boss painter draws besides the boss: under the score, the boss's
## name and its bar (one pip per bounce still to go, SimConfig.BOSS_POINTS in
## all); while the bird waits in the portal, the boss's title card. UI ink on
## the room (white in night worlds), never the spike colour. Looks only.

const Boss := preload("res://sim/hazards/boss.gd")

const NAME_Y := 124.0
const PIPS_Y := 132.0
const PIP := Vector2(6.0, 10.0)
const PIP_GAP := 3.0
const TITLE_Y := 410.0
## Steps the title card takes to fade after the hold.
const TITLE_FADE := 24.0


static func ink(look: HazardLook) -> Color:
	return UiTokens.ON_SCRIM if look.theme.night else UiTokens.ON_SKY


static func draw(c: CanvasItem, h: Boss, look: HazardLook) -> void:
	if look.sim == null:
		return
	var sim := look.sim
	var col := ink(look)
	var name := RoomInfo.name_of(sim.room.def.id)
	var font := GameFonts.ui(800)
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var tag := name.to_upper()
	var size := UiTokens.FONT_SIZE_TAG
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(
		font, Vector2((w - tw) / 2.0, NAME_Y), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col
	)
	var left := clampi(sim.next_exit_score() - sim.state.score, 0, SimConfig.BOSS_POINTS)
	if h.down_at >= 0:
		left = 0
	var n := SimConfig.BOSS_POINTS
	var x0 := (w - (n * (PIP.x + PIP_GAP) - PIP_GAP)) / 2.0
	for i in n:
		var r := Rect2(x0 + i * (PIP.x + PIP_GAP), PIPS_Y, PIP.x, PIP.y)
		var on := i < left
		UiTheme.flat(col if on else Color(col, 0.22), 2, 0).draw(c.get_canvas_item(), r)
	_title(c, h, look, name)


## The title card over the waiting room: "BOSS · 100", the name, a line.
static func _title(c: CanvasItem, h: Boss, look: HazardLook, name: String) -> void:
	var sim := look.sim
	var a := 1.0
	if sim.state.arrival_hold <= 0 or h.t > 0:
		a = 1.0 - h.t / TITLE_FADE
	if a <= 0.0 or sim.room.points > 0:
		return
	var col := Color(ink(look), a)
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var tag := "BOSS · %d" % sim.room.entry_score
	var small := GameFonts.ui(800)
	var tw := small.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.FONT_SIZE_TAG).x
	var pill := Rect2((w - tw) / 2.0 - 9.0, TITLE_Y - 18.0, tw + 18.0, 20.0)
	UiTheme.flat(col, UiTokens.RADIUS_S, 0).draw(c.get_canvas_item(), pill)
	var on_pill := Color(UiTokens.ON_PRIMARY if not look.theme.night else UiTokens.ON_SKY, a)
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
	c.draw_string(
		big, Vector2((w - nw) / 2.0, TITLE_Y + 40.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col
	)
	var line := "Break it in %d bounces" % SimConfig.BOSS_POINTS
	var lf := GameFonts.ui(700)
	var lw := lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.FONT_SIZE_LABEL).x
	c.draw_string(
		lf,
		Vector2((w - lw) / 2.0, TITLE_Y + 68.0),
		line,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTokens.FONT_SIZE_LABEL,
		col
	)


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
