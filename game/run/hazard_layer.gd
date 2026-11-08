class_name HazardLayer
extends Node2D
## Draws the room's hazards from sim state. Each hazard kind has a painter in
## game/run/painters/<kind>_painter.gd with
##   static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float)
## Rule from the design kit: anything deadly is drawn in the world's spike
## color; safe things (bumpers, bubbles, coins) never are.

const PAINTER_DIR := "res://game/run/painters"

static var _painters := {}

var _run: RunController
var _theme: ThemeDef
var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func bind(run: RunController, theme: ThemeDef) -> void:
	_run = run
	_theme = theme
	queue_redraw()


func set_theme(theme: ThemeDef) -> void:
	_theme = theme
	queue_redraw()


static func painter_path(kind: String) -> String:
	return PAINTER_DIR.path_join(kind + "_painter.gd")


static func painter(kind: String) -> Script:
	if not _painters.has(kind):
		var path := painter_path(kind)
		_painters[kind] = load(path) if ResourceLoader.exists(path) else null
	return _painters[kind]


static func release() -> void:
	_painters.clear()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _run == null or _run.sim == null or _theme == null:
		return
	for h in _run.sim.room.hazards:
		if not h.alive:
			continue
		var p := painter(h.kind)
		if p != null:
			p.paint(self, h, _theme, _time)


## Sub-units to pixels.
static func px(v: int) -> float:
	return v / float(SimConfig.SUB)


static func at(x: int, y: int) -> Vector2:
	return Vector2(px(x), px(y))


## A spiked circle: the shared look of deadly round things (balls, saws).
static func spiky_ball(
	c: CanvasItem, center: Vector2, r: float, theme: ThemeDef, spin: float
) -> void:
	var teeth := 12
	var pts := PackedVector2Array()
	for i in teeth * 2:
		var a := spin + TAU * i / (teeth * 2)
		var rr := r if i % 2 == 0 else r * 0.72
		pts.append(center + Vector2.RIGHT.rotated(a) * rr)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_circle(center, r * 0.55, Color(theme.spike_edge, 0.55))


## A rounded deadly box with a lighter top edge.
static func rock_box(c: CanvasItem, rect: Rect2, theme: ThemeDef, alpha: float = 1.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(theme.spike, alpha)
	box.set_corner_radius_all(int(minf(8.0, rect.size.y / 2.0)))
	box.border_color = Color(theme.spike_edge, 0.8 * alpha)
	box.border_width_top = 3
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), rect)
