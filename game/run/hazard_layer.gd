class_name HazardLayer
extends Node2D
## Draws the room's hazards from sim state. Each hazard kind has a painter in
## game/run/painters/<kind>_painter.gd (a HazardPainter); it gets a HazardLook
## with the world, the clock, the room's skin (RoomSkins) and color-blind mode.
## Rule from the design kit: anything deadly is drawn in the world's spike
## color; safe things (bumpers, bubbles, coins) never are.
## Color-blind spikes (Settings): painters get a copy of the world whose spike
## colour is ink and whose spike-edge is white, and `look.ink` on, so deadly
## things turn dark with white edges, like RoomView's spikes.

const PAINTER_DIR := "res://game/run/painters"
const INK_EDGE := Color("#FFFFFF")
const INK_LINE_W := 2.0
const GUIDE_ALPHA := 0.22

static var _painters: Dictionary[String, HazardPainter] = {}

## Color-blind spikes: hazards in ink with white edges.
var color_blind_spikes := false:
	set(value):
		color_blind_spikes = value
		queue_redraw()

## Where the HUD's run score starts (Hud.score_placed), for painters that
## draw under it (the boss bar).
var score_top := HazardLook.RUN_SCORE_TOP

var _run: RunController
var _theme: ThemeDef
var _ink_theme: ThemeDef
var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func bind(run: RunController, theme: ThemeDef) -> void:
	_run = run
	set_theme(theme)


func set_theme(theme: ThemeDef) -> void:
	_theme = theme
	_ink_theme = ink_theme(theme)
	queue_redraw()


## The world as color-blind spikes draw it: ink spikes with a white edge.
static func ink_theme(theme: ThemeDef) -> ThemeDef:
	var t: ThemeDef = theme.duplicate()
	t.spike = RoomView.INK_SPIKE
	t.spike_edge = INK_EDGE
	return t


## The world the painters get (the ink copy when color-blind spikes are on).
func drawn_theme() -> ThemeDef:
	return _ink_theme if color_blind_spikes else _theme


## What the painters get this frame.
func look() -> HazardLook:
	var skin := ""
	if _run != null and _run.sim != null and _run.sim.room.def != null:
		skin = RoomSkins.of(_run.sim.room.def.id)
	var out := HazardLook.new(drawn_theme(), _time, skin, color_blind_spikes)
	out.sim = _run.sim if _run != null else null
	out.score_top = score_top
	return out


static func painter_path(kind: String) -> String:
	return PAINTER_DIR.path_join(kind + "_painter.gd")


## The painter for hazard kind `kind`, or null when there is none.
static func painter(kind: String) -> HazardPainter:
	if not _painters.has(kind):
		var path := painter_path(kind)
		var script := load(path) as GDScript if ResourceLoader.exists(path) else null
		_painters[kind] = script.new() as HazardPainter if script != null else null
	return _painters[kind]


static func release() -> void:
	_painters.clear()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _run == null or _run.sim == null or _theme == null:
		return
	var hazard_look := look()
	for h in _run.sim.room.hazards:
		if not h.alive:
			continue
		var p := painter(h.kind)
		if p != null:
			p.paint(self, h, hazard_look)


## A safe guide line (a track, a rail, a ring something rides on): the
## world's text ink, faint, so it reads on light and night skies alike and is
## never mistaken for a hazard.
static func guide(theme: ThemeDef) -> Color:
	return Color(theme.ink, GUIDE_ALPHA)


## Sub-units to pixels.
static func px(v: int) -> float:
	return v / float(SimConfig.SUB)


static func at(x: int, y: int) -> Vector2:
	return Vector2(px(x), px(y))


## A spiked circle: the shared look of deadly round things (balls, saws).
static func spiky_ball(
	c: CanvasItem, center: Vector2, r: float, look: HazardLook, spin: float
) -> void:
	var theme := look.theme
	var teeth := 12
	var pts := PackedVector2Array()
	for i in teeth * 2:
		var a := spin + TAU * i / (teeth * 2)
		var rr := r if i % 2 == 0 else r * 0.72
		pts.append(center + Vector2.RIGHT.rotated(a) * rr)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	if look.ink:
		c.draw_polyline(pts, INK_EDGE, INK_LINE_W, true)
	else:
		c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_circle(center, r * 0.55, Color(theme.spike_edge, 0.55))


## A rounded deadly box with a lighter top edge.
static func rock_box(c: CanvasItem, rect: Rect2, look: HazardLook, alpha: float = 1.0) -> void:
	var theme := look.theme
	var box := StyleBoxFlat.new()
	box.bg_color = Color(theme.spike, alpha)
	box.set_corner_radius_all(int(minf(8.0, rect.size.y / 2.0)))
	box.border_color = Color(theme.spike_edge, 0.8 * alpha)
	box.border_width_top = 3
	if look.ink:
		# Color-blind spikes: a white edge all round.
		box.border_color = Color(INK_EDGE, alpha)
		box.set_border_width_all(int(INK_LINE_W))
		box.border_width_top = 3
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), rect)
