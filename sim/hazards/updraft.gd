extends Hazard
## A column of moving air (Updraft room). While the bird's center is inside the
## band, every step adds `lift` to its upward speed (a negative lift pulls it
## down: a downdraft). Never deadly itself; the ceiling and floor still are.
##
## Variants (catalog_sky.gd) set where the band is, how wide and how strong,
## and can make it drift wall to wall (drift_span) or blow in gusts
## (gust: off, then a warning, then on).

enum Gust { NONE, OFF, WARN, ON }

const SUB := SimConfig.SUB
## Today's band: 120 px wide in the middle.
const HALF_W := 60 * SUB
## Soft lift: two thirds of gravity, the bird still sinks slowly. Tied to
## SimConfig.GRAVITY so a physics change keeps the balance.
const LIFT := SimConfig.GRAVITY * 2 / 3
## Hover: lift equals gravity, the bird keeps its vertical speed.
const HOVER := SimConfig.GRAVITY
## Chimney: one and a half gravity, the bird is carried up. At this strength the
## forced first flap out of a practice start or a revive still clears the
## ceiling; a fresh flap just before the column does not.
const CHIMNEY := SimConfig.GRAVITY * 3 / 2
## Gusts: twice gravity, the bird is thrown up (after a 1 s warning).
const STRONG := SimConfig.GRAVITY * 2
## Gust timing, steps: off, then the warning (ARRIVAL_BLIND, the same 1 s a
## player gets out of a portal), then on.
const GUST_OFF := 60
const GUST_WARN := SimConfig.ARRIVAL_BLIND
const GUST_ON := 90
const GUST_PERIOD := GUST_OFF + GUST_WARN + GUST_ON
## A rising band (a gust, a chimney, a hover or soft lane; not a drifting one)
## lifts the bird as it crosses: a wall drawn while it will lift the bird on
## its way there keeps a free run (the room's gap, or as much
## of it as fits) from GUST_UP_REACH above to GUST_DOWN_REACH below the bottom
## of the last wall's free run (the gust cycle is on screen, so a player can
## come off that wall low), and no higher than GUST_TOP (a thrown bird would
## not get back down from the ceiling).
const GUST_UP_REACH := 160 * SUB
const GUST_DOWN_REACH := 40 * SUB
const GUST_TOP := 160 * SUB

## Band edges, sub-units (they move when the band drifts).
var x0 := 0
var x1 := 0
var half_w := HALF_W
## Upward speed added per step while inside (negative: pulled down).
var lift := LIFT
## Drift: the band's center moves between drift_min and drift_min + drift_span
## and back, 1 px per step. 0 = it stays put.
var drift_min := 0
var drift_span := 0
## The air acts from y0 down to y1 (the whole column by default). Generated
## variants cut it short of a bird's band out of a portal: rising air starts
## below it, falling air stops above it. The painter draws it to these lines.
var y0 := SimConfig.KILL_TOP
var y1 := SimConfig.KILL_BOTTOM
## Gust: NONE = always on; otherwise where in its cycle it is.
var gust := Gust.NONE
## Steps into the cycle (drift or gust), drawn at setup.
var phase := 0
## Bottom (centre of its lowest slot) of the free run of the last wall drawn,
## or -1 before the room's first wall.
var last_low := -1


func _init(
	p_center: int = SimConfig.WORLD_W / 2, p_half_w: int = HALF_W, p_lift: int = LIFT
) -> void:
	kind = "updraft"
	half_w = p_half_w
	lift = p_lift
	_place(p_center)


## Drifts the band's center between `p_min` and `p_min + p_span`.
func drifting(p_min: int, p_span: int) -> Hazard:
	drift_min = p_min
	drift_span = p_span
	_place(p_min)
	return self


## Blows in gusts (off, warning, on) instead of all the time.
func gusty() -> Hazard:
	gust = Gust.OFF
	return self


func setup(_sim: GameSim, rng: SimRng) -> void:
	if drift_span > 0:
		phase = rng.next_below(_drift_period())
	elif gust != Gust.NONE:
		# Always starts in the off part, so a full warning comes before the first gust.
		phase = rng.next_below(GUST_OFF)
	_update()


func step(_sim: GameSim) -> void:
	_update()


func blowing() -> bool:
	return gust == Gust.NONE or gust == Gust.ON


func inside(sim: GameSim) -> bool:
	return sim.state.x >= x0 and sim.state.x <= x1 and sim.state.y >= y0 and sim.state.y <= y1


## Generated variants, out of a portal: keeps the air off the band a bird
## holding its height sweeps (rising air starts below it, falling air stops
## above it).
func clear_band(p: VariantParams) -> void:
	if lift > 0:
		y0 = p.hold_bottom()
	else:
		y1 = p.hold_top()


func touch(sim: GameSim) -> void:
	if blowing() and inside(sim):
		var vy := sim.state.vy - lift
		sim.state.vy = clampi(vy, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)


## Gusts: keeps the wall the bird flies to within reach of a bird the gust
## lifts on the way (GUST_DOWN_REACH). The gust is fixed by time and the bird's
## x by its speed, so every player of a seed gets the same wall. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var out := mask
	if lift > 0 and drift_span == 0 and _gust_on_way(sim, side):
		var low := last_low if last_low >= 0 else sim.state.anchor_y
		var ok := 0
		for slot in SimConfig.SLOT_COUNT:
			var y := SimConfig.slot_center_y(slot)
			if y >= maxi(GUST_TOP, low - GUST_UP_REACH) and y <= low + GUST_DOWN_REACH:
				ok |= 1 << slot
		var all := (1 << SimConfig.SLOT_COUNT) - 1
		var need := mini(sim.room.def.gap, RoomRules.longest_gap(all & ~ok))
		out = RoomRules.keep_run(mask, need, ok)
	var run := RoomRules.longest_gap_mask(out)
	for slot in SimConfig.SLOT_COUNT:
		if (run >> slot) & 1 == 1:
			last_low = SimConfig.slot_center_y(slot)
	return out


## True if the band lifts the bird at some step it is inside it, flying
## straight to wall `side` (a band without gusts always does; a gusty one when
## its gust blows then).
func _gust_on_way(sim: GameSim, side: int) -> bool:
	var at := sim.steps_to_wall(side)
	var dir := 1 if side == 1 else -1
	for k in at + 1:
		var bx := sim.state.x + dir * k * SimConfig.SPEED_X
		if bx >= x0 and bx <= x1:
			if gust == Gust.NONE or posmod(t + k + phase, GUST_PERIOD) >= GUST_OFF + GUST_WARN:
				return true
	return false


## Steps into the gust cycle (0 .. GUST_PERIOD - 1).
func gust_step() -> int:
	return posmod(t + phase, GUST_PERIOD)


func _update() -> void:
	if drift_span > 0:
		_place(drift_min + SimTrig.ping_pong(t + phase, _drift_period(), drift_span))
	if gust != Gust.NONE:
		var m := gust_step()
		if m < GUST_OFF:
			gust = Gust.OFF
		elif m < GUST_OFF + GUST_WARN:
			gust = Gust.WARN
		else:
			gust = Gust.ON


## A full drift there and back at 1 px per step.
func _drift_period() -> int:
	return 2 * drift_span / SUB


func _place(center: int) -> void:
	x0 = center - half_w
	x1 = center + half_w


func checksum(h: int) -> int:
	var out := mix_all(h, [x0, x1, lift, drift_min, drift_span, gust, phase, last_low])
	if y0 != SimConfig.KILL_TOP or y1 != SimConfig.KILL_BOTTOM:
		out = mix_all(out, [y0, y1])
	return out


## A gusty vent during its warning: the column, for the gust (a push, not a kill).
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if gust != Gust.WARN:
		return
	var eta := GUST_OFF + GUST_WARN - gust_step()
	add_warning(out, x0, y0, x1, y1, eta, GUST_ON, WARN_PUSH)
