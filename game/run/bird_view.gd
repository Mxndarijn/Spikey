class_name BirdView
extends Node2D
## Draws the player's flyer (CharacterDef art), interpolated between the last
## two sim ticks. Every flyer shares the sim hitbox (SimConfig.BIRD_RADIUS);
## this view only decides how it looks.

const FLAP_POSE_TIME := 0.12
## How far the body stretches on a flap / squashes on a wall bounce.
const FLAP_STRETCH := 0.18
const BOUNCE_SQUASH := 0.22
const SQUASH_RECOVER := 7.0
## Nose-up angle right after a flap and nose-down angle at full fall speed (radians).
const TILT_UP := 0.55
const TILT_DOWN := 1.05
const TILT_FOLLOW := 12.0
## Flyer art is drawn on a 120-unit canvas; this scale makes the body about
## UiTokens.SIZE_BIRD (32px) wide.
const ART_SCALE := 0.6
const ART_CANVAS := 120.0
const DEAD_TINT := Color(0.8, 0.8, 0.85)
## Seconds a flyer takes to fade when its crash effect replaces it.
const FADE_OUT_TIME := 0.15

var _run: RunController
var _character: CharacterDef
var _flap_timer := 0.0
var _shake := 0.0
var _bob_time := 0.0
## Positive = taller and thinner (flap), negative = wider and flatter (bounce).
var _stretch := 0.0
var _tilt := 0.0
var _fading := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func bind(run: RunController, character: CharacterDef) -> void:
	_run = run
	_character = character
	_flap_timer = 0.0
	_shake = 0.0
	_stretch = 0.0
	_tilt = 0.0
	_fading = false
	modulate.a = 1.0
	queue_redraw()


func set_character(character: CharacterDef) -> void:
	_character = character
	queue_redraw()


func on_flap() -> void:
	_flap_timer = FLAP_POSE_TIME
	_stretch = FLAP_STRETCH


func on_bounce() -> void:
	_stretch = -BOUNCE_SQUASH


func on_death() -> void:
	_shake = 0.3


## The flyer fades away (crash effects that turn it into pieces); bind() brings
## it back for the next run.
func fade_out() -> void:
	_fading = true


## Target tilt for a vertical speed: nose up while rising, nose down while falling.
static func tilt_for(vy: int) -> float:
	if vy < 0:
		return -TILT_UP * clampf(float(vy) / SimConfig.FLAP_VY, 0.0, 1.0)
	return TILT_DOWN * clampf(float(vy) / SimConfig.MAX_FALL_VY, 0.0, 1.0)


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	if _fading:
		modulate.a = move_toward(modulate.a, 0.0, delta / FADE_OUT_TIME)
	_flap_timer = maxf(_flap_timer - delta, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	_bob_time += delta
	var s := _run.sim.state
	var t := Engine.get_physics_interpolation_fraction()
	var prev := _run.prev_state
	# Going through a portal moves the bird to the other wall in one step: show it
	# there at once instead of sliding it across the room.
	if absi(s.x - prev.x) > SimConfig.WORLD_W / 2:
		t = 1.0
	var px := lerpf(prev.x, s.x, t) / SimConfig.SUB
	var py := lerpf(prev.y, s.y, t) / SimConfig.SUB
	if not s.started:
		py += sin(_bob_time * 5.0) * 4.0
	elif s.arrival_hold > 0:
		# Waiting in a portal: the same idle bob, easing out as the wait ends.
		py += sin(_bob_time * 5.0) * 4.0 * minf(1.0, s.arrival_hold / 12.0)
	if _shake > 0.0:
		px += randf_range(-3, 3)
		py += randf_range(-3, 3)
	position = Vector2(px, py)
	var facing := 1.0 if s.vx > 0 else -1.0
	_stretch = move_toward(_stretch, 0.0, delta * SQUASH_RECOVER * absf(_stretch) + delta * 0.2)
	scale = Vector2(facing * (1.0 - _stretch), 1.0 + _stretch)
	# Ease toward the target so a flap swings the nose up instead of snapping it.
	var target := tilt_for(s.vy) if s.started else 0.0
	_tilt = lerpf(_tilt, target, 1.0 - exp(-TILT_FOLLOW * delta))
	rotation = _tilt * facing
	queue_redraw()


func _draw() -> void:
	if _character == null:
		return
	var tex := _character.flap if _flap_timer > 0.0 and _character.flap != null else _character.idle
	if tex == null:
		return
	var size := ART_CANVAS * ART_SCALE
	var dead := _run != null and _run.sim != null and _run.sim.is_over()
	draw_texture_rect(
		tex, Rect2(-size / 2.0, -size / 2.0, size, size), false, DEAD_TINT if dead else Color.WHITE
	)
