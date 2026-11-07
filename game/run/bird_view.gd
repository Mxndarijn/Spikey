class_name BirdView
extends Node2D
## Draws the placeholder bird, interpolated between the last two sim ticks.
## Every character will share the sim hitbox (SimConfig.BIRD_RADIUS);
## this view only decides how it looks.

const BODY_R := 16.0
const FLAP_POSE_TIME := 0.12
## How far the body stretches on a flap / squashes on a wall bounce.
const FLAP_STRETCH := 0.18
const BOUNCE_SQUASH := 0.22
const SQUASH_RECOVER := 7.0
const TILT_MAX := 0.45
const TILT_FOLLOW := 14.0
## Placeholder character art. Characters will bring their own (data/characters/).
const COLORS := {
	"body": Color("#FF5E7E"),
	"belly": Color("#FFD0D9"),
	"wing": Color("#D83A63"),
	"beak": Color("#FFB52E"),
	"beak_dark": Color("#E58F0C"),
	"blush": Color("#FFB0C0"),
	"eye": Color("#1E1B2E"),
}

var _run: RunController
var _flap_timer := 0.0
var _shake := 0.0
var _bob_time := 0.0
## Positive = taller and thinner (flap), negative = wider and flatter (bounce).
var _stretch := 0.0
var _tilt := 0.0


func bind(run: RunController) -> void:
	_run = run
	_flap_timer = 0.0
	_shake = 0.0
	_stretch = 0.0
	_tilt = 0.0


func on_flap() -> void:
	_flap_timer = FLAP_POSE_TIME
	_stretch = FLAP_STRETCH


func on_bounce() -> void:
	_stretch = -BOUNCE_SQUASH


func on_death() -> void:
	_shake = 0.3


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	_flap_timer = maxf(_flap_timer - delta, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	_bob_time += delta
	var s := _run.sim.state
	var t := Engine.get_physics_interpolation_fraction()
	var prev := _run.prev_state
	var px := lerpf(prev.x, s.x, t) / SimConfig.SUB
	var py := lerpf(prev.y, s.y, t) / SimConfig.SUB
	if not s.started:
		py += sin(_bob_time * 5.0) * 4.0
	if _shake > 0.0:
		px += randf_range(-3, 3)
		py += randf_range(-3, 3)
	position = Vector2(px, py)
	var facing := 1.0 if s.vx > 0 else -1.0
	_stretch = move_toward(_stretch, 0.0, delta * SQUASH_RECOVER * absf(_stretch) + delta * 0.2)
	scale = Vector2(facing * (1.0 - _stretch), 1.0 + _stretch)
	# Ease the tilt toward the velocity so a flap doesn't snap the bird's nose up.
	var target := 0.0
	if s.started:
		target = clampf(float(s.vy) / SimConfig.MAX_FALL_VY, -1.0, 1.0) * TILT_MAX
	_tilt = lerpf(_tilt, target, 1.0 - exp(-TILT_FOLLOW * delta))
	rotation = _tilt * facing
	queue_redraw()


func _draw() -> void:
	var c := COLORS
	var dead := _run != null and _run.sim != null and _run.sim.is_over()
	# Tail
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(-14, 0), Vector2(-23, -6), Vector2(-21, 1), Vector2(-25, 6), Vector2(-13, 7)]
		),
		c.wing
	)
	draw_circle(Vector2.ZERO, BODY_R, c.body)
	draw_set_transform(Vector2(3, 6), 0.0, Vector2(1.0, 0.7))
	draw_circle(Vector2.ZERO, 10.5, c.belly)
	draw_set_transform(Vector2(9, 4), 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, 3.0, Color(c.blush, 0.75))
	draw_set_transform(Vector2.ZERO)
	# Beak
	draw_colored_polygon(
		PackedVector2Array([Vector2(13, -2), Vector2(24, 0), Vector2(13, 4)]), c.beak
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(13, 3), Vector2(19, 5), Vector2(12, 6)]), c.beak_dark
	)
	# Eye
	if dead:
		draw_line(Vector2(3, -8), Vector2(10, -1), c.eye, 2.2)
		draw_line(Vector2(10, -8), Vector2(3, -1), c.eye, 2.2)
	else:
		draw_set_transform(Vector2(6, -4), 0.0, Vector2(0.9, 1.0))
		draw_circle(Vector2.ZERO, 6.2, Color.WHITE)
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2(8.3, -3.6), 3.4, c.eye)
		draw_circle(Vector2(9.4, -5.6), 1.2, Color.WHITE)
	# Wing: up pose right after a flap.
	var wing := (
		PackedVector2Array([Vector2(-9, 2), Vector2(-8, -11), Vector2(-1, -12), Vector2(-1, 2)])
		if _flap_timer > 0.0
		else PackedVector2Array([Vector2(-10, 1), Vector2(2, -2), Vector2(2, 4), Vector2(-9, 8)])
	)
	draw_colored_polygon(wing, c.wing)
