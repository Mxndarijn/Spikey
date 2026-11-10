extends Hazard
## A four-blade pinwheel turning steadily in the middle of the room (Pinwheel).
## The hub and every blade kill. Blades are tested as a row of circles.

const CENTER_X := 180 * SimConfig.SUB
const CENTER_Y := 320 * SimConfig.SUB
const BLADES := 4
const HUB_RADIUS := 16 * SimConfig.SUB
const BLADE_LENGTH := 80 * SimConfig.SUB
## Half the blade's width, also the radius of each test circle.
const BLADE_HALF_W := 8 * SimConfig.SUB
## Test circles per blade, spread from the hub to the tip.
const SAMPLES := 5
## Steps per full turn.
const PERIOD := 360
## Out of a portal the pinwheel sits at least this far above or below the
## bird (blade, bird and a margin), so a player still holding height while
## reading the room flies past it.
const HUB_CLEAR := BLADE_LENGTH + BLADE_HALF_W + SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB
## Holding height, the bird hops about this far up: more room on that side.
const HOP := 64 * SimConfig.SUB

## Hub height: CENTER_Y, or moved off the bird's height out of a portal.
var center_y := CENTER_Y
var phase := 0
## +1 or -1: which way it turns.
var dir := 1
## Current turn (SimTrig angle of blade 0).
var angle := 0


func _init() -> void:
	kind = "rotor"


func setup(sim: GameSim, rng: SimRng) -> void:
	center_y = CENTER_Y
	var dy := sim.state.y - CENTER_Y
	if sim.state.started and dy > -HUB_CLEAR and dy < HUB_CLEAR + HOP:
		center_y = sim.state.y + (HUB_CLEAR if dy < 0 else -HUB_CLEAR - HOP)
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	angle = posmod(phase + dir * (t * SimTrig.TURN / PERIOD), SimTrig.TURN)


func blade_angle(i: int) -> int:
	return angle + i * SimTrig.TURN / BLADES


func kills(sim: GameSim) -> bool:
	if sim.bird_touches_circle(CENTER_X, center_y, HUB_RADIUS):
		return true
	for i in BLADES:
		var a := blade_angle(i)
		var c := SimTrig.cos_t(a)
		var s := SimTrig.sin_t(a)
		for k in SAMPLES:
			var d := BLADE_LENGTH * (k + 1) / SAMPLES
			var px := CENTER_X + d * c / SimTrig.ONE
			var py := center_y + d * s / SimTrig.ONE
			if sim.bird_touches_circle(px, py, BLADE_HALF_W):
				return true
	return false


func checksum(h: int) -> int:
	return mix_all(h, [phase, dir, angle, center_y])
