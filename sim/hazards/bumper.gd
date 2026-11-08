extends Hazard
## A soft cloud that drifts round a slow loop (Bumper Cloud; Heart Bumpers is
## the same with a skin). Safe to touch, but it shoves the bird away hard.

const RADIUS := 28 * SimConfig.SUB
## The loop: an ellipse round the middle of the room, clear of the walls,
## ceiling and floor, so it never sits on the bird at a wall.
const CENTER_X := 180 * SimConfig.SUB
const CENTER_Y := 320 * SimConfig.SUB
const LOOP_RX := 80 * SimConfig.SUB
const LOOP_RY := 140 * SimConfig.SUB
## Steps per lap.
const PERIOD := 600

var x := 0
var y := 0
## Where on the loop it starts (SimTrig angle) and which way it goes (+1 / -1).
var phase := 0
var dir := 1


func _init() -> void:
	kind = "bumper"


func setup(_sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var a := phase + dir * (t * SimTrig.TURN / PERIOD)
	x = CENTER_X + LOOP_RX * SimTrig.cos_t(a) / SimTrig.ONE
	y = CENTER_Y + LOOP_RY * SimTrig.sin_t(a) / SimTrig.ONE


func touch(sim: GameSim) -> void:
	if sim.bird_touches_circle(x, y, RADIUS):
		sim.bump_bird_from(x, y)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, phase, dir])
