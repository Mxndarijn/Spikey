class_name CrashView
extends Node2D
## Plays the equipped crash effect (a CrashStyle, drawn by CrashPainter) where
## the flyer ended its run. It starts after the sim has ended the run and only
## knows where the flyer was drawn, so it never touches gameplay.

var style: CrashStyle

var _time := 0.0
var _origin := Vector2.ZERO
var _away := 1.0
var _palette := PackedColorArray()
var _playing := false


## Starts the effect at `at` (the drawn flyer). `away`: +1 when pieces should
## fly right, -1 left. `palette`: the flyer's own colours, for Shatter.
func play(
	crash_style: CrashStyle,
	at: Vector2,
	away: float,
	palette: PackedColorArray = PackedColorArray()
) -> void:
	style = crash_style
	_origin = at
	_away = away
	_palette = palette
	_time = 0.0
	_playing = style != null
	# Behind the flyer by default (this node comes before BirdView); styles
	# drawn in front go one layer up.
	z_index = 1 if style != null and style.in_front else 0
	queue_redraw()


## Stops and hides the effect (a new run starts).
func clear() -> void:
	_playing = false
	queue_redraw()


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	if not style.loops() and _time > style.duration():
		_playing = false
	queue_redraw()


func _draw() -> void:
	if _playing:
		CrashPainter.paint(self, style, _time, _origin, _away, 1.0, 1.0, _palette)
