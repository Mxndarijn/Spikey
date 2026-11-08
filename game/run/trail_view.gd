class_name TrailView
extends Node2D
## Draws a fading trail behind the bird, styled by a TrailStyle (see TrailPainter).
## Follows the drawn bird position, so it never touches gameplay.

const WORLD_HEAD_ALPHA := 0.85
## The bird moves a few pixels a frame; a bigger jump means it went through a
## portal to the other wall, so the trail starts over instead of drawing a line
## across the room.
const JUMP_DISTANCE := 100.0

var style := TrailStyle.world_ribbon()

var _bird: Node2D
var _head := Color.WHITE
var _tail := Color.TRANSPARENT
var _points := PackedVector2Array()
var _ages := PackedFloat32Array()
var _emitting := true


func bind(bird: Node2D, trail_style: TrailStyle, theme: ThemeDef) -> void:
	_bird = bird
	style = trail_style
	set_theme(theme)
	_points.clear()
	_ages.clear()
	_emitting = false


func set_style(trail_style: TrailStyle, theme: ThemeDef) -> void:
	style = trail_style
	set_theme(theme)


func set_theme(theme: ThemeDef) -> void:
	if style.use_world_color:
		_head = Color(theme.trail, WORLD_HEAD_ALPHA)
		_tail = Color(theme.trail, 0.0)
	else:
		_head = style.head_color
		_tail = style.tail_color


## Starts adding points (when the run starts).
func start() -> void:
	_emitting = true


## Stops adding points (e.g. on death); the trail fades out.
func stop() -> void:
	_emitting = false


func _process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[0] > style.lifetime:
		_points.remove_at(0)
		_ages.remove_at(0)
	if _emitting and not style.stamp_on_flap and _bird != null and _bird.is_visible_in_tree():
		var p := _bird.position
		if _points.size() > 0 and _points[_points.size() - 1].distance_to(p) > JUMP_DISTANCE:
			_points.clear()
			_ages.clear()
		var last := _points.size() - 1
		if last < 0 or _points[last].distance_to(p) >= style.spacing:
			_points.append(p)
			_ages.append(0.0)
		elif last >= 0:
			_points[last] = p
	queue_redraw()


func _draw() -> void:
	TrailPainter.paint(self, _points, _ages, style, _head, _tail)


## Stamp-on-flap trails (Music Notes) leave one stamp per flap.
func on_flap() -> void:
	if style.stamp_on_flap and _emitting and _bird != null:
		_points.append(_bird.position)
		_ages.append(0.0)
