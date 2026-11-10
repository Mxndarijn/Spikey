class_name NightView
extends Node2D
## Midnight Cage's Lantern and Flicker variants: the room goes dark except a
## circle of light round the flyer (Flicker: the circle pulses). Drawn above
## the room, hazards, coins and trail, below the flyer. Cosmetic only.
##
## Fairness: the light is too small to see a wall coming in time (the cage
## runs at 1.25 times speed), so the spikes of the wall ahead glow through
## the dark for the whole crossing, the wall behind faintly, and an open exit
## glows too. The player always sees where the gap is about a second ahead.

## Lantern: the light's radius, px.
const LANTERN_R := 90.0
## Flicker: the light swings between these radii, once per FLICKER_TIME s
## (with reduced flashing it stays at the middle).
const FLICKER_MIN := 95.0
const FLICKER_MAX := 150.0
const FLICKER_TIME := 1.4
## The dark itself and the soft rim of the light, px.
const DARK := Color("#08061E")
const DARK_ALPHA := 0.9
const RIM := 28.0
## Far enough to cover any phone's surround; points round the circle.
const COVER := 2400.0
const SEGMENTS := 64
## Spike outlines: the wall ahead, the wall behind.
const GLOW_AHEAD := 0.95
const GLOW_BEHIND := 0.35
const GLOW_W := 2.5
## Ceiling and floor: a faint line where they start to kill.
const EDGE_ALPHA := 0.35

var _run: RunController
var _room: RoomView
var _bird: BirdView
var _time := 0.0


func bind(run: RunController, room: RoomView, bird: BirdView) -> void:
	_run = run
	_room = room
	_bird = bird


## The light's radius in this room right now, px, or 0 when the room isn't
## dark (any room but Midnight Cage's Lantern and Flicker).
func light_radius() -> float:
	if _run == null or _run.sim == null:
		return 0.0
	var room := _run.sim.room
	if room.def.id != "midnight":
		return 0.0
	match room.variant_id():
		"lantern":
			return LANTERN_R
		"flicker":
			if not _room.flash_enabled:
				return (FLICKER_MIN + FLICKER_MAX) / 2.0
			var k := 0.5 + 0.5 * sin(_time * TAU / FLICKER_TIME)
			return lerpf(FLICKER_MIN, FLICKER_MAX, k)
	return 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var r := light_radius()
	if r <= 0.0:
		return
	_draw_dark(_bird.position, r)
	_draw_glow()


## Three rings of points round the light (clear inside, then dark at `r`,
## then far out), joined into one triangle mesh with no overlaps.
func _draw_dark(center: Vector2, r: float) -> void:
	var radii := [r - RIM, r, COVER]
	var alphas := [0.0, DARK_ALPHA, DARK_ALPHA]
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for ring in 3:
		for i in SEGMENTS:
			var a := TAU * i / SEGMENTS
			points.append(center + Vector2(cos(a), sin(a)) * float(radii[ring]))
			colors.append(Color(DARK, float(alphas[ring])))
	var indices := PackedInt32Array()
	for ring in 2:
		for i in SEGMENTS:
			var a0 := ring * SEGMENTS + i
			var a1 := ring * SEGMENTS + (i + 1) % SEGMENTS
			var b0 := a0 + SEGMENTS
			var b1 := a1 + SEGMENTS
			indices.append_array([a0, a1, b1, a0, b1, b0])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)


## What must stay readable in the dark: the spikes of both walls (the one
## ahead bright), an open exit, and the ceiling and floor lines.
func _draw_glow() -> void:
	var sim := _run.sim
	var theme := _room.current_theme()
	var glow := theme.world_accent
	var ahead := 1 if sim.state.vx > 0 else 0
	var room := sim.room
	var half := RoomView.SPIKE_HALF * room.spike_half_base() / SimConfig.SPIKE_HALF_BASE
	var depth := RoomView.SPIKE_DEPTH * room.spike_depth() / SimConfig.SPIKE_DEPTH
	for side in 2:
		var col := Color(glow, GLOW_AHEAD if side == ahead else GLOW_BEHIND)
		var x := _room.side_wall_x(side)
		var dir := 1.0 if side == 0 else -1.0
		var mask := sim.wall_mask(side)
		var shift := sim.wall_shift(side) / float(SimConfig.SUB)
		for slot in SimConfig.SLOT_COUNT:
			if not RoomRules.has_slot(mask, slot):
				continue
			var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB) + shift
			var pts := RoomView.spike_points(Vector2(x, cy), Vector2(dir, 0), half, depth)
			draw_polyline(pts, col, GLOW_W, true)
	var s := sim.state
	if s.exit_open:
		var ex := _room.side_wall_x(s.exit_side)
		var half_h := SimConfig.EXIT_HALF / float(SimConfig.SUB)
		var ys: Array[int] = [s.exit_a_y]
		if s.exit_b_kind != SimState.ExitKind.NORMAL:
			ys.append(s.exit_b_y)
		for y in ys:
			var c := Vector2(ex, y / float(SimConfig.SUB))
			draw_line(c - Vector2(0, half_h), c + Vector2(0, half_h), glow, GLOW_W * 2.0, true)
	var edge := Color(glow, EDGE_ALPHA)
	var top := SimConfig.KILL_TOP / float(SimConfig.SUB)
	var bottom := SimConfig.KILL_BOTTOM / float(SimConfig.SUB)
	draw_line(Vector2(0, top), Vector2(RoomView.W, top), edge, GLOW_W)
	draw_line(Vector2(0, bottom), Vector2(RoomView.W, bottom), edge, GLOW_W)
