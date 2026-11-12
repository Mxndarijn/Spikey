extends Hazard
## Peg Field: one round spiked peg, placed by the room's recipe (CatalogCaves)
## when the room starts and never moved, but for the drift variant's bob: the
## whole field rises and sinks together by `bob` on one slow wave, its phase
## fixed when the room starts, so the gaps between pegs never change. All of
## it kills.

const SUB := SimConfig.SUB
## Its spike tips.
const RADIUS := 19 * SUB
## Drift: steps per bob, up and down.
const BOB_PERIOD := 240

var x := 0
var base_y := 0
## How far it bobs either way (0: still), and where in the bob it starts.
var bob := 0
var phase := 0
## Its centre height now.
var y := 0


func _init(p_x: int = 0, p_y: int = 0, p_bob: int = 0, p_phase: int = 0) -> void:
	kind = "peg"
	x = p_x
	base_y = p_y
	bob = p_bob
	phase = p_phase
	y = p_y


func setup(_sim: GameSim, _rng: SimRng) -> void:
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	if bob == 0:
		y = base_y
		return
	var a := (t + phase) * SimTrig.TURN / BOB_PERIOD
	y = base_y + bob * SimTrig.sin_t(a) / SimTrig.ONE


func kills(sim: GameSim) -> bool:
	return sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	return mix_all(h, [x, base_y, bob, phase, y])
