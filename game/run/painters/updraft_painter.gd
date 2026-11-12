extends HazardPainter
## Updraft: a soft column with chevrons. Air is safe, so it never uses the
## spike colour: rising air is the world's glow (brighter and faster when it is
## strong), a downdraft is faint ink with chevrons pointing down. A gust column
## shows a dashed outline and a vent while off, then fills from the floor with
## a bar on the vent during its 1 s warning.

const UpdraftHazard := preload("res://sim/hazards/updraft.gd")

const ROWS := 8
const SPEED := 70.0
## Strong air (above gravity) moves its chevrons this much faster.
const STRONG_SPEED := 2.2
const VENT_H := 8.0
const DASH := 10.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as UpdraftHazard
	var theme := look.theme
	var time := look.time
	var x0 := HazardLayer.px(h.x0)
	var x1 := HazardLayer.px(h.x1)
	# The column runs band to band (behind the spike rows' tips), so it does
	# not stop in mid-air a few px short of the ceiling and floor.
	var top := RoomView.BAND
	var bottom := RoomView.H - RoomView.BAND
	# A generated column cut short of the bird's band ends where its air ends.
	if h.y0 > SimConfig.KILL_TOP:
		top = HazardLayer.px(h.y0)
	if h.y1 < SimConfig.KILL_BOTTOM:
		bottom = HazardLayer.px(h.y1)
	var w := x1 - x0
	var down := h.lift < 0
	var strong := h.lift > SimConfig.GRAVITY
	var tint := theme.ink if down else theme.glow
	var speed := SPEED * (STRONG_SPEED if strong else 1.0)

	if h.gust == UpdraftHazard.Gust.OFF or h.gust == UpdraftHazard.Gust.WARN:
		_dashed_edges(c, x0, x1, top, bottom, Color(theme.paper, 0.35))
		var vent_y := HazardLayer.px(SimConfig.KILL_BOTTOM) - VENT_H - 30
		var vent := Rect2(x0 + 10, vent_y, w - 20, VENT_H)
		c.draw_rect(vent, Color(theme.paper, 0.45))
		if h.gust == UpdraftHazard.Gust.WARN:
			var f := float(h.gust_step() - UpdraftHazard.GUST_OFF) / UpdraftHazard.GUST_WARN
			var fill_top := bottom - (bottom - top) * f
			c.draw_rect(Rect2(x0, fill_top, w, bottom - fill_top), Color(theme.glow, 0.18))
			_chevrons(c, x0, x1, fill_top, bottom, time, speed, false, Color(theme.paper, 0.8))
			c.draw_rect(Rect2(vent.position, Vector2(vent.size.x * f, VENT_H)), theme.ink)
		return

	var fill := 0.2 if strong else 0.10
	c.draw_rect(Rect2(x0, top, w, bottom - top), Color(tint, fill))
	# Soft edges: two thin lines at the band's sides.
	var edge := Color(tint, 0.30 if not strong else 0.5)
	c.draw_line(Vector2(x0, top), Vector2(x0, bottom), edge, 2.0, true)
	c.draw_line(Vector2(x1, top), Vector2(x1, bottom), edge, 2.0, true)
	_chevrons(c, x0, x1, top, bottom, time, speed, down, Color(tint, 0.45 if down else 0.55))


func _chevrons(
	c: CanvasItem,
	x0: float,
	x1: float,
	top: float,
	bottom: float,
	time: float,
	speed: float,
	down: bool,
	col: Color
) -> void:
	var span := bottom - top
	if span <= 1.0:
		return
	var w := x1 - x0
	var cx := (x0 + x1) / 2.0
	var rows := maxi(1, roundi(ROWS * span / 572.0))
	for i in rows:
		var off := fposmod(time * speed + i * span / rows, span)
		var y := top + off if down else bottom - off
		var fade := clampf((y - top) / 60.0, 0.0, 1.0) * clampf((bottom - y) / 60.0, 0.0, 1.0)
		var half := w * 0.18
		var d := -10.0 if down else 10.0
		var pts := PackedVector2Array(
			[Vector2(cx - half, y + d), Vector2(cx, y), Vector2(cx + half, y + d)]
		)
		c.draw_polyline(pts, Color(col, col.a * fade), 3.0, true)


func _dashed_edges(
	c: CanvasItem, x0: float, x1: float, top: float, bottom: float, col: Color
) -> void:
	for x: float in [x0, x1]:
		c.draw_dashed_line(Vector2(x, top), Vector2(x, bottom), col, 2.0, DASH)
