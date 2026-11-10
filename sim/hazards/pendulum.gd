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
## Out of a portal: evenly spaced swings tried, to keep the lantern off the
## arrival path (FairLanes.arrival_path).
const ARRIVAL_TRIES := 32

var phase := 0
## Current swing angle (SimTrig units, 0 = straight down, + = to the right).
var angle := 0
## Lantern centre.
var x := 0
var y := 0


func _init() -> void:
	kind = "pendulum"


func setup(sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(SimTrig.TURN)
	# Out of a portal: the first swing that keeps the lantern off the arrival
	# lane (else see FairLanes.ARRIVAL_PATH_MIN; else the swing drawn).
	if sim.state.started:
		var arrival := FairLanes.arrival_path(sim)
		var first := phase
		var pick := phase
		var settled := false
		for k in ARRIVAL_TRIES:
			phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN
			var clear := _arrival_clear(arrival)
			if clear >= FairLanes.ARRIVAL_PATH_TICKS:
				pick = phase
				break
			if clear >= FairLanes.ARRIVAL_PATH_MIN and not settled:
				pick = phase
				settled = true
		phase = pick
	_place()


## Steps until the lantern first comes near the arrival path
## (FairLanes.arrival_path), or ARRIVAL_PATH_TICKS if it doesn't.
func _arrival_clear(arrival: PackedInt32Array) -> int:
	var keep := t
	var out := FairLanes.ARRIVAL_PATH_TICKS
	for k in FairLanes.ARRIVAL_PATH_TICKS:
		t = k
		_place()
		if FairLanes.arrival_path_hits(arrival, k, x, y, RADIUS):
			out = k
			break
	t = keep
	_place()
	return out


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
