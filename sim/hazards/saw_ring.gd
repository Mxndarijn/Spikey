extends Hazard
## 4 or 5 saws circling a centre point (Saw Ring). The ring breathes on a fixed
## schedule: small, grow, wide, shrink. Every saw kills.

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

## Ring centre height: CENTER_Y, or moved off the bird's height out of a portal.
var center_y := CENTER_Y
var count := 4
var phase := 0
var dir := 1
var radius := RING_MIN
## Ring turn (SimTrig angle of saw 0).
var angle := 0
## Saw centres (filled every step for the painter).
var xs: Array[int] = []
var ys: Array[int] = []


func _init() -> void:
	kind = "saw_ring"


func setup(sim: GameSim, rng: SimRng) -> void:
	center_y = CENTER_Y
	var y := sim.state.y
	if sim.state.started and y - CENTER_Y > -ARRIVAL_CLEAR and y - CENTER_Y < ARRIVAL_CLEAR + HOP:
		# Below the bird if the ring still fits above the floor, else above it.
		center_y = y + ARRIVAL_CLEAR
		if center_y + RING_MAX + SAW_RADIUS > SimConfig.KILL_BOTTOM:
			center_y = y - ARRIVAL_CLEAR - HOP
	count = 4 + rng.next_below(2)
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	xs.resize(count)
	ys.resize(count)
	_place()


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


func _place() -> void:
	radius = radius_at(t)
	angle = posmod(phase + dir * (t * SimTrig.TURN / PERIOD), SimTrig.TURN)
	for i in count:
		var a := angle + i * SimTrig.TURN / count
		xs[i] = CENTER_X + radius * SimTrig.cos_t(a) / SimTrig.ONE
		ys[i] = center_y + radius * SimTrig.sin_t(a) / SimTrig.ONE


func kills(sim: GameSim) -> bool:
	for i in count:
		if sim.bird_touches_circle(xs[i], ys[i], SAW_RADIUS):
			return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(h, [count, phase, dir, radius, angle, center_y])
	for i in count:
		out = mix_all(out, [xs[i], ys[i]])
	return out
