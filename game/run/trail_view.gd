class_name TrailView
extends Node2D
## Draws a fading trail behind the bird, styled by a TrailStyle.
## Follows the drawn bird position, so it never touches gameplay.

var style := TrailStyle.sunset_ribbon()

var _bird: Node2D
var _points := PackedVector2Array()
var _ages := PackedFloat32Array()
var _emitting := true


func bind(bird: Node2D, trail_style: TrailStyle = null) -> void:
	_bird = bird
	if trail_style != null:
		style = trail_style
	_points.clear()
	_ages.clear()
	_emitting = false


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
	if _emitting and _bird != null and _bird.is_visible_in_tree():
		var p := _bird.position
		var last := _points.size() - 1
		if last < 0 or _points[last].distance_to(p) >= style.spacing:
			_points.append(p)
			_ages.append(0.0)
		elif last >= 0:
			_points[last] = p
	queue_redraw()


func _draw() -> void:
	if _points.size() < 2:
		return
	match style.kind:
		TrailStyle.Kind.RIBBON:
			_draw_ribbon()
		TrailStyle.Kind.DOTS:
			_draw_dots()


func _fade(i: int) -> float:
	return clampf(1.0 - _ages[i] / style.lifetime, 0.0, 1.0)


func _draw_ribbon() -> void:
	var n := _points.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors := PackedColorArray()
	for i in n:
		var a := _points[maxi(i - 1, 0)]
		var b := _points[mini(i + 1, n - 1)]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var f := _fade(i)
		var w := style.width * 0.5 * f
		left.append(_points[i] + normal * w)
		right.append(_points[i] - normal * w)
		colors.append(style.tail_color.lerp(style.head_color, f))
	# Two triangles per segment via draw_primitive: no triangulation, so thin or
	# folded segments at sharp turns can't fail to draw.
	var no_uv := PackedVector2Array()
	for i in n - 1:
		draw_primitive(
			PackedVector2Array([left[i], left[i + 1], right[i + 1]]),
			PackedColorArray([colors[i], colors[i + 1], colors[i + 1]]),
			no_uv
		)
		draw_primitive(
			PackedVector2Array([left[i], right[i + 1], right[i]]),
			PackedColorArray([colors[i], colors[i + 1], colors[i]]),
			no_uv
		)


func _draw_dots() -> void:
	for i in _points.size():
		var f := _fade(i)
		draw_circle(_points[i], style.width * 0.5 * f, style.tail_color.lerp(style.head_color, f))
