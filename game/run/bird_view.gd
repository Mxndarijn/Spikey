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
## Landing on a Lava Rise raft: the body squashes down (shorter, wider).
const LAND_SQUASH := 0.25
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
## Seconds the flyer takes to turn upside down (or back) when gravity flips.
const FLIP_TIME := 0.2
## Game over (GameOverStage): the flyer leaves the wall and floats to a spot in
## the middle, SHOW_SCALE times its size, tilted and dazed with stars circling
## its head; on a new best it bobs instead.
const SHOW_SCALE := 1.8
const SHOW_TILT := 0.26
const SHOW_BOB := 4.0
const STAR_COUNT := 3
const STAR_ORBIT := Vector2(15.0, 3.0)
const STAR_Y := -20.0
const STAR_R := 3.2
const STAR_SPIN := 2.2

var _run: RunController
var _character: CharacterDef
var _flap_timer := 0.0
var _shake := 0.0
var _bob_time := 0.0
## Positive = taller and thinner (flap).
var _stretch := 0.0
## A wall bounce: the body squeezes against the wall (narrower along x, a bit
## taller), so it never pokes into a wall band (Narrow, Squeeze Box) when it
## turns round. 0..BOUNCE_SQUASH, easing back like the stretch.
var _squash := 0.0
## A raft landing (RaftLanding): 0..LAND_SQUASH, easing back like the squash.
var _land := 0.0
## RaftLanding's memory of the rafts that were up.
var _rafts_up := {}
var _tilt := 0.0
var _fading := false
## Flip progress: 1 = upright, -1 = upside down (Gravity Flip). Moves linearly;
## flip_scale() eases it for drawing.
var _flip := 1.0
## Game over showcase: on, where it flies from and to, progress 0..1, the
## flight's length (0: at once), dazed (stars) or happy (bob), still (reduced
## motion: no bob, the stars stand still).
var _show := false
var _show_from := Vector2.ZERO
var _show_to := Vector2.ZERO
var _show_t := 1.0
var _show_time := 0.0
var _dazed := true
var _still := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func bind(run: RunController, character: CharacterDef) -> void:
	_run = run
	_character = character
	_flap_timer = 0.0
	_shake = 0.0
	_stretch = 0.0
	_squash = 0.0
	_land = 0.0
	_rafts_up.clear()
	_tilt = 0.0
	_fading = false
	_show = false
	# A new run starts in its room's gravity at once, no flip animation.
	_flip = flip_target(_gravity_sign())
	modulate.a = 1.0
	queue_redraw()


func set_character(character: CharacterDef) -> void:
	_character = character
	queue_redraw()


func on_flap() -> void:
	_flap_timer = FLAP_POSE_TIME
	_stretch = FLAP_STRETCH


func on_bounce() -> void:
	_squash = BOUNCE_SQUASH


func on_raft_landing() -> void:
	_land = LAND_SQUASH


## Squashes the body when the bird lands on a raft (the sim uses a raft up on
## its touch; RaftLanding tells). Returns whether it did.
func watch_rafts(sim: GameSim) -> bool:
	var hit := false
	for h in sim.room.hazards:
		var lava := h as RaftLanding.LavaHazard
		if lava != null and not RaftLanding.landed(lava, _rafts_up).is_empty():
			hit = true
	if hit:
		on_raft_landing()
	return hit


func on_death() -> void:
	_shake = 0.3


## The flyer fades away (crash effects that turn it into pieces); bind() or
## on_revived() brings it back.
func fade_out() -> void:
	_fading = true


## Game over: float to `spot` and grow (see SHOW_SCALE) over `time` seconds,
## dazed or, on a new best, happy. A flyer its crash effect hid fades back in
## at the spot.
func showcase(spot: Vector2, dazed: bool, still: bool, time: float) -> void:
	_show = true
	_show_from = position
	_show_to = spot
	_show_time = time
	_show_t = 0.0 if time > 0.0 else 1.0
	_dazed = dazed
	_still = still
	_shake = 0.0
	if _fading:
		_fading = false
		_show_from = spot
		modulate.a = 0.0 if time > 0.0 else 1.0
	queue_redraw()


func is_showcased() -> bool:
	return _show


## The flyer's size, place and tilt in the showcase at progress `t` (0..1,
## eased), facing +1 right or -1 left.
static func showcase_pose(from: Vector2, to: Vector2, t: float, facing: float) -> Dictionary:
	var e := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
	var k := lerpf(1.0, SHOW_SCALE, e)
	return {
		"position": from.lerp(to, e),
		"scale": Vector2(facing * k, k),
		"rotation": SHOW_TILT * facing * e,
	}


## The bird was revived: show the flyer again at once, even if its crash
## effect had faded it away.
func on_revived() -> void:
	_fading = false
	_show = false
	_shake = 0.0
	modulate.a = 1.0
	queue_redraw()


## Target tilt for a vertical speed: nose up while rising, nose down while falling.
static func tilt_for(vy: int) -> float:
	if vy < 0:
		return -TILT_UP * clampf(float(vy) / SimConfig.FLAP_VY, 0.0, 1.0)
	return TILT_DOWN * clampf(float(vy) / SimConfig.MAX_FALL_VY, 0.0, 1.0)


## Flip progress the flyer heads for: upside down while gravity points up.
static func flip_target(gravity_sign: int) -> float:
	return -1.0 if gravity_sign < 0 else 1.0


## One frame of the flip: moves `current` toward `target` so a full turn
## (1 to -1) takes FLIP_TIME seconds.
static func flip_step(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, delta * 2.0 / FLIP_TIME)


## Vertical scale for a flip progress: eased so the turn starts and ends softly
## and passes edge-on (0) halfway.
static func flip_scale(progress: float) -> float:
	return sin(clampf(progress, -1.0, 1.0) * PI / 2.0)


## Body rotation for a tilt, the facing (+1 right, -1 left) and the drawn flip
## scale. Upside down the rotation mirrors too, so the nose still points the
## way the flyer moves.
static func rotation_for(tilt: float, facing: float, flip: float) -> float:
	return tilt * facing * flip


## How far between the last two sim ticks to draw the flyer. While the sim
## stands still (run over or paused) the physics fraction keeps cycling, so the
## flyer stays on the latest tick instead of sliding back and forth.
static func blend_fraction(run: RunController, physics_fraction: float) -> float:
	if run.paused or run.sim.is_over():
		return 1.0
	return run.blend_fraction(physics_fraction)


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	if _show:
		_process_showcase(delta)
		return
	if _fading:
		modulate.a = move_toward(modulate.a, 0.0, delta / FADE_OUT_TIME)
	_flap_timer = maxf(_flap_timer - delta, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	_bob_time += delta
	var s := _run.sim.state
	var t := blend_fraction(_run, Engine.get_physics_interpolation_fraction())
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
	_squash = move_toward(_squash, 0.0, delta * SQUASH_RECOVER * _squash + delta * 0.2)
	watch_rafts(_run.sim)
	_land = move_toward(_land, 0.0, delta * SQUASH_RECOVER * _land + delta * 0.2)
	var g := _gravity_sign()
	_flip = flip_step(_flip, flip_target(g), delta)
	var flip := flip_scale(_flip)
	var sx := (1.0 - _stretch) * (1.0 - _squash) * (1.0 + _land * 0.6)
	var sy := (1.0 + _stretch) * (1.0 + _squash * 0.5) * (1.0 - _land)
	scale = Vector2(facing * sx, sy * flip)
	# Ease toward the target so a flap swings the nose up instead of snapping it.
	# Tilt is measured along gravity: "falling" is toward the ceiling when flipped.
	var target := tilt_for(s.vy * g) if s.started else 0.0
	_tilt = lerpf(_tilt, target, 1.0 - exp(-TILT_FOLLOW * delta))
	rotation = rotation_for(_tilt, facing, flip)
	queue_redraw()


func _process_showcase(delta: float) -> void:
	_bob_time += delta
	if _show_time > 0.0:
		_show_t = minf(_show_t + delta / _show_time, 1.0)
		modulate.a = minf(modulate.a + delta / _show_time, 1.0)
	var facing := 1.0 if _run.sim.state.vx > 0 else -1.0
	var pose := showcase_pose(_show_from, _show_to, _show_t, facing)
	position = pose.position
	scale = pose.scale
	rotation = pose.rotation
	if not _dazed and not _still and _show_t >= 1.0:
		position.y += sin(_bob_time * 3.0) * SHOW_BOB
	queue_redraw()


## The current room's gravity: 1 down, -1 up (Gravity Flip).
func _gravity_sign() -> int:
	if _run == null or _run.sim == null or _run.sim.room == null:
		return 1
	return _run.sim.room.def.gravity_sign


func _draw() -> void:
	if _character == null:
		return
	var tex := _character.flap if _flap_timer > 0.0 and _character.flap != null else _character.idle
	if tex == null:
		return
	var size := ART_CANVAS * ART_SCALE
	var dead := _run != null and _run.sim != null and _run.sim.is_over() and not _show
	draw_texture_rect(
		tex, Rect2(-size / 2.0, -size / 2.0, size, size), false, DEAD_TINT if dead else Color.WHITE
	)
	if _show and _dazed and _show_t >= 1.0:
		_draw_stars()


## Dazed: small gold stars circling the flyer's head (standing still with
## reduced motion).
func _draw_stars() -> void:
	var spin := 0.0 if _still else _bob_time * STAR_SPIN
	for i in STAR_COUNT:
		var a := spin + TAU * i / STAR_COUNT
		var c := Vector2(cos(a) * STAR_ORBIT.x, STAR_Y + sin(a) * STAR_ORBIT.y)
		var pts := PackedVector2Array()
		for j in 8:
			var r := STAR_R if j % 2 == 0 else STAR_R * 0.4
			var b := TAU * j / 8.0 - PI / 2.0
			pts.append(c + Vector2(cos(b), sin(b)) * r)
		draw_colored_polygon(pts, UiTokens.ACTION)
