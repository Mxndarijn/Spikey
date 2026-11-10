extends Hazard
## 4 or 5 saws circling a centre point (Saw Ring). The ring breathes on a fixed
## schedule: small, grow, wide, shrink. Every saw kills.
##
## Variants set the fields after new(): a fixed saw count, another centre x, a
## flat oval (ry_num / ry_den of the width), a faster lap, or a small inner
## ring of smaller saws turning the other way. SawRing.new() as is plays the
## original ring (Saw Ring classic, Double Trouble).

const CENTER_X := 180 * SimConfig.SUB
const CENTER_Y := 320 * SimConfig.SUB
const SAW_RADIUS := 18 * SimConfig.SUB
## Ring radius range: wide still keeps every saw inside x 70..290 px, so the
## bird has room by each wall to line up with the gap.
const RING_MIN := 50 * SimConfig.SUB
const RING_MAX := 92 * SimConfig.SUB
## Schedule in steps: hold small, grow, hold wide, shrink.
const HOLD := 60
## Grow and shrink take 1.5 s each (playtest: 1 s came back too fast).
const MOVE := 90
const CYCLE := 2 * (HOLD + MOVE)
## Steps per lap of the ring.
const PERIOD := 300
## Out of a portal the ring sits at least this far below the bird, or this
## plus HOP above it (holding height, the bird hops about HOP up), so a player
## still reading the room flies past every saw.
const ARRIVAL_CLEAR := RING_MAX + SAW_RADIUS + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB
const HOP := 64 * SimConfig.SUB

## Shape (variants change these before setup()).
var center_x := CENTER_X
var ring_min := RING_MIN
var ring_max := RING_MAX
var saw_radius := SAW_RADIUS
var period := PERIOD
## Saws on the ring; 0 = 4 or 5 from the RNG.
var fixed_count := 0
## Height of the orbit as a fraction of its width (oval when below 1).
var ry_num := 1
var ry_den := 1
## Inner ring: saws, radius range (breathes with the outer ring), saw radius.
## It turns the other way.
var inner_count := 0
var inner_min := 0
var inner_max := 0
var inner_saw := 0

## Ring centre height: CENTER_Y, or moved off the bird's height out of a portal.
var center_y := CENTER_Y
var count := 4
var phase := 0
var dir := 1
var radius := RING_MIN
var inner_radius := 0
## Ring turn (SimTrig angle of saw 0).
var angle := 0
## Saw centres, outer ring first, then the inner ring (filled every step for
## the painter).
var xs: Array[int] = []
var ys: Array[int] = []


func _init() -> void:
	kind = "saw_ring"


func setup(sim: GameSim, rng: SimRng) -> void:
	center_y = CENTER_Y
	var y := sim.state.y
	var clear := arrival_clear()
	if sim.state.started and y - CENTER_Y > -clear and y - CENTER_Y < clear + HOP:
		# Below the bird if the ring still fits above the floor, else above it.
		center_y = y + clear
		if center_y + reach_y() > SimConfig.KILL_BOTTOM:
			center_y = y - clear - HOP
	count = 4 + rng.next_below(2)
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	if fixed_count > 0:
		count = fixed_count
	xs.resize(count + inner_count)
	ys.resize(count + inner_count)
	_place()


## How far the saws reach above and below the centre at the widest.
func reach_y() -> int:
	var out := ring_max * ry_num / ry_den + saw_radius
	if inner_count > 0:
		out = maxi(out, inner_max * ry_num / ry_den + inner_saw)
	return out


## How far below the bird the ring sits out of a portal.
func arrival_clear() -> int:
	return reach_y() + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB


func step(_sim: GameSim) -> void:
	_place()


## Ring radius at step `tick` on the fixed schedule.
static func radius_at(tick: int) -> int:
	var p := posmod(tick, CYCLE)
	var span := RING_MAX - RING_MIN
	if p < HOLD:
		return RING_MIN
	p -= HOLD
	if p < MOVE:
		return RING_MIN + span * p / MOVE
	p -= MOVE
	if p < HOLD:
		return RING_MAX
	p -= HOLD
	return RING_MAX - span * p / MOVE


## Radius between `lo` and `hi` at the same point of the schedule.
static func scaled(tick: int, lo: int, hi: int) -> int:
	return lo + (hi - lo) * (radius_at(tick) - RING_MIN) / (RING_MAX - RING_MIN)


func _place() -> void:
	radius = scaled(t, ring_min, ring_max)
	angle = posmod(phase + dir * (t * SimTrig.TURN / period), SimTrig.TURN)
	for i in count:
		var a := angle + i * SimTrig.TURN / count
		xs[i] = center_x + radius * SimTrig.cos_t(a) / SimTrig.ONE
		ys[i] = center_y + radius * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE
	if inner_count == 0:
		return
	inner_radius = scaled(t, inner_min, inner_max)
	var back := posmod(phase - dir * (t * SimTrig.TURN / period), SimTrig.TURN)
	for i in inner_count:
		var a := back + i * SimTrig.TURN / inner_count
		xs[count + i] = center_x + inner_radius * SimTrig.cos_t(a) / SimTrig.ONE
		ys[count + i] = (center_y + inner_radius * SimTrig.sin_t(a) * ry_num / ry_den / SimTrig.ONE)


## Radius of saw `i` (inner saws can be smaller).
func saw_r(i: int) -> int:
	return saw_radius if i < count else inner_saw


func kills(sim: GameSim) -> bool:
	for i in count + inner_count:
		if sim.bird_touches_circle(xs[i], ys[i], saw_r(i)):
			return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(h, [count, phase, dir, radius, angle, center_y])
	for i in count:
		out = mix_all(out, [xs[i], ys[i]])
	if inner_count > 0 or center_x != CENTER_X or period != PERIOD or ry_num != ry_den:
		out = mix_all(out, [center_x, period, ry_num, ry_den, inner_count, inner_radius])
		for i in inner_count:
			out = mix_all(out, [xs[count + i], ys[count + i]])
	return out
