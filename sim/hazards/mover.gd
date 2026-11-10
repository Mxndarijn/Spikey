extends Hazard
## Small deadly creatures moving on a fixed path (seasonal rooms).
## mode "figure8": a lissajous figure-eight through the middle (Halloween Bat
## Loop, skin "bat"). mode "wave": they cross from wall to wall on a sine wave
## and turn back (Spring Bee Line, skin "bee"). Positions depend only on `t`
## and one phase drawn in setup(). Paths stay clear of the side walls, so they
## never start on the bird.

const SUB := SimConfig.SUB
const RADIUS := 12 * SUB
## Room kept between a creature and the bird's first hop, and how many evenly
## spaced phases to try.
const START_MARGIN := 10 * SUB
const PHASE_TRIES := 16
## Evenly spaced phases tried out of a portal.
const ARRIVAL_TRIES := 60
const CENTER_X := 180 * SUB
const CENTER_Y := 320 * SUB
# Figure-eight.
const LOOP_W := 80 * SUB
const LOOP_H := 90 * SUB
const LOOP_PERIOD := 480
# Wave.
const WAVE_MIN_X := 96 * SUB
const WAVE_MAX_X := 264 * SUB
const WAVE_PERIOD := 300
const WAVE_AMP := 70 * SUB
const WAVE_TURNS := 3
## Steps between creatures following each other on the wave.
const WAVE_SPACING := 22

var mode := "figure8"
var count := 3
var phase := 0
var xs: Array[int] = []
var ys: Array[int] = []
## -1 facing left, 1 facing right (painters flip the art).
var facing: Array[int] = []


func _init(p_mode: String = "figure8", p_count: int = 3) -> void:
	kind = "mover"
	mode = p_mode
	count = p_count
	for i in count:
		xs.append(0)
		ys.append(0)
		facing.append(1)


func setup(sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(period())
	# Shift along the path until no creature meets the bird's first hop (the
	# room waits for the first tap, then both start moving together).
	# Out of a portal: until none meets the arrival path (else see
	# GameSim.ARRIVAL_PATH_MIN; else the phase drawn).
	var path := sim.start_path()
	var arrival := sim.arrival_path() if sim.state.started else PackedInt32Array()
	var first := phase
	var tries := ARRIVAL_TRIES if sim.state.started else PHASE_TRIES
	var pick := phase
	var settled := false
	for k in tries:
		phase = (first + k * period() / tries) % period()
		if sim.state.started:
			var clear := _arrival_clear(arrival)
			if clear >= GameSim.ARRIVAL_PATH_TICKS:
				pick = phase
				break
			if clear >= GameSim.ARRIVAL_PATH_MIN and not settled:
				pick = phase
				settled = true
		elif not _meets_path(path):
			break
	if sim.state.started:
		phase = pick
	_place()


## Whether a creature touches the start path (x, y pairs per step) at the step
## the bird is there, with a little room to spare.
func _meets_path(path: PackedInt32Array) -> bool:
	var keep := t
	var reach := SimConfig.BIRD_RADIUS + RADIUS + START_MARGIN
	var hit := false
	for i in range(0, path.size(), 2):
		t = i / 2 + 1
		_place()
		for c in count:
			var dx := xs[c] - path[i]
			var dy := ys[c] - path[i + 1]
			if dx * dx + dy * dy < reach * reach:
				hit = true
		if hit:
			break
	t = keep
	return hit


## Steps until a creature first comes near the arrival path (GameSim.arrival_path),
## or ARRIVAL_PATH_TICKS if none does.
func _arrival_clear(arrival: PackedInt32Array) -> int:
	var keep := t
	var out := GameSim.ARRIVAL_PATH_TICKS
	for k in GameSim.ARRIVAL_PATH_TICKS:
		t = k
		_place()
		for c in count:
			if GameSim.arrival_path_hits(arrival, k, xs[c], ys[c], RADIUS):
				out = k
		if out < GameSim.ARRIVAL_PATH_TICKS:
			break
	t = keep
	return out


func period() -> int:
	return LOOP_PERIOD if mode == "figure8" else WAVE_PERIOD


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	for i in count:
		var nx := 0
		var ny := 0
		if mode == "figure8":
			var a := (t + phase) * SimTrig.TURN / LOOP_PERIOD + i * SimTrig.TURN / count
			nx = CENTER_X + LOOP_W * SimTrig.sin_t(a) / SimTrig.ONE
			ny = CENTER_Y + LOOP_H * SimTrig.sin_t(2 * a) / SimTrig.ONE
		else:
			var k := t + phase - i * WAVE_SPACING
			nx = WAVE_MIN_X + SimTrig.ping_pong(k, WAVE_PERIOD, WAVE_MAX_X - WAVE_MIN_X)
			var a := k * SimTrig.TURN * WAVE_TURNS / WAVE_PERIOD
			ny = CENTER_Y + WAVE_AMP * SimTrig.sin_t(a) / SimTrig.ONE
		if nx != xs[i]:
			facing[i] = 1 if nx > xs[i] else -1
		xs[i] = nx
		ys[i] = ny


func kills(sim: GameSim) -> bool:
	for i in count:
		if sim.bird_touches_circle(xs[i], ys[i], RADIUS):
			return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(h, [count, phase, int(mode == "figure8")])
	for i in count:
		out = mix_all(out, [xs[i], ys[i], facing[i]])
	return out
