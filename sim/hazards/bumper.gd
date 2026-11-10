extends Hazard
## A soft cloud that drifts round a slow loop (Bumper Cloud; Heart Bumpers is
## the same with a skin). Safe to touch, but it shoves the bird away hard.
## Heart Bumpers' variants change its size and loop: one big heart on a
## narrower loop (big), or two that circle the middle (orbit).

const RADIUS := 28 * SimConfig.SUB
## The loop: an ellipse round the middle of the room, clear of the walls,
## ceiling and floor, so it never sits on the bird at a wall.
const CENTER_X := 180 * SimConfig.SUB
const CENTER_Y := 320 * SimConfig.SUB
const LOOP_RX := 80 * SimConfig.SUB
const LOOP_RY := 140 * SimConfig.SUB
## Steps per lap.
const PERIOD := 600
## One big heart: 1.5 times the size, on a loop narrow enough that it still
## never sits on the bird at a wall.
const BIG_RADIUS := 42 * SimConfig.SUB
const BIG_LOOP_RX := 56 * SimConfig.SUB
const BIG_PERIOD := 720
## Orbiting hearts: a round loop about the middle, a little quicker.
const ORBIT_R := 96 * SimConfig.SUB
const ORBIT_PERIOD := 480

var radius := RADIUS
var loop_rx := LOOP_RX
var loop_ry := LOOP_RY
var period := PERIOD

var x := 0
var y := 0
## Where on the loop it starts (SimTrig angle) and which way it goes (+1 / -1).
var phase := 0
var dir := 1
## A second cloud: it rides the same loop as the cloud before it in the room,
## on the opposite side, so the two never meet.
var follows := false


func _init(p_follows: bool = false) -> void:
	kind = "bumper"
	follows = p_follows


## Makes this a big bumper on a narrower loop.
func big() -> Hazard:
	radius = BIG_RADIUS
	loop_rx = BIG_LOOP_RX
	period = BIG_PERIOD
	return self


## Makes this a bumper circling the middle.
func orbit() -> Hazard:
	loop_rx = ORBIT_R
	loop_ry = ORBIT_R
	period = ORBIT_PERIOD
	return self


func setup(sim: GameSim, rng: SimRng) -> void:
	if follows:
		for h in sim.room.hazards:
			if h != self and h.kind == kind:
				phase = h.phase + SimTrig.TURN / 2
				dir = h.dir
				_place()
				return
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var a := phase + dir * (t * SimTrig.TURN / period)
	x = CENTER_X + loop_rx * SimTrig.cos_t(a) / SimTrig.ONE
	y = CENTER_Y + loop_ry * SimTrig.sin_t(a) / SimTrig.ONE


func touch(sim: GameSim) -> void:
	if sim.bird_touches_circle(x, y, radius):
		sim.bump_bird_from(x, y)


func checksum(h: int) -> int:
	var out := mix_all(h, [x, y, phase, dir, int(follows)])
	if radius != RADIUS or loop_rx != LOOP_RX or loop_ry != LOOP_RY or period != PERIOD:
		out = mix_all(out, [radius, loop_rx, loop_ry, period])
	return out
