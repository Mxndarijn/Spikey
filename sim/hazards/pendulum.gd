extends Hazard
## A lantern on a chain swinging from the ceiling through the middle of the
## room (Lantern Swing). The lantern kills; the chain is safe.

const PIVOT_X := 180 * SimConfig.SUB
const PIVOT_Y := SimConfig.KILL_TOP
const LENGTH := 280 * SimConfig.SUB
const RADIUS := 22 * SimConfig.SUB
## Widest swing as a SimTrig angle (70/1024 of a turn, about 25 degrees): the
## lantern stays inside x 40..320 px, clear of a bird at either wall.
const AMPLITUDE := 52
## Steps per full swing (there and back).
const PERIOD := 180

var phase := 0
## Current swing angle (SimTrig units, 0 = straight down, + = to the right).
var angle := 0
## Lantern centre.
var x := 0
var y := 0


func _init() -> void:
	kind = "pendulum"


func setup(_sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(SimTrig.TURN)
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	angle = AMPLITUDE * SimTrig.sin_t(phase + t * SimTrig.TURN / PERIOD) / SimTrig.ONE
	x = PIVOT_X + LENGTH * SimTrig.sin_t(angle) / SimTrig.ONE
	y = PIVOT_Y + LENGTH * SimTrig.cos_t(angle) / SimTrig.ONE


func kills(sim: GameSim) -> bool:
	return sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	return mix_all(h, [phase, angle, x, y])
