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
## Out of a portal: the bird's way is kept clear this long (a player still
## reading the room, then a second to steer), from ARRIVAL_UP above it
## (it hops while holding height) to just below it.
const ARRIVAL_TICKS := SimConfig.ARRIVAL_BLIND + 60
## Evenly spaced phases tried out of a portal.
const ARRIVAL_TRIES := 60
const ARRIVAL_UP := 75 * SUB
const ARRIVAL_DOWN := 18 * SUB
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
	# Out of a portal: until no creature meets the bird flying straight on.
	var path := sim.start_path()
	var first := phase
	var tries := ARRIVAL_TRIES if sim.state.started else PHASE_TRIES
	for k in tries:
		phase = (first + k * period() / tries) % period()
		if sim.state.started:
			if not _meets_arrival(sim):
				break
		elif not _meets_path(path):
			break
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


## Whether a creature comes near the bird's way out of a portal in its first
## ARRIVAL_TICKS steps: flying straight on, between ARRIVAL_UP above its height
## and ARRIVAL_DOWN below.
func _meets_arrival(sim: GameSim) -> bool:
	var keep := t
	var st := sim.state
	var g := sim.room.def.gravity_sign
	var top := mini(st.y - ARRIVAL_UP * g, st.y + ARRIVAL_DOWN * g)
	var bottom := maxi(st.y - ARRIVAL_UP * g, st.y + ARRIVAL_DOWN * g)
	var reach := SimConfig.BIRD_RADIUS + RADIUS
	var hit := false
	for k in ARRIVAL_TICKS:
		t = k
		_place()
		var bx := st.x + st.vx * k
		for c in count:
			var near_y := clampi(ys[c], top, bottom)
			var dx := xs[c] - bx
			var dy := ys[c] - near_y
			if dx * dx + dy * dy < reach * reach:
				hit = true
		if hit:
			break
	t = keep
	return hit


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
