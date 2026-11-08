extends Hazard
## A spiked drop that falls straight down a column (Spike Rain; Orchard Drop's
## pinecone and Winter's icicle are skins). First the column is marked on the
## ceiling for WARN steps, then it falls fast. Only the falling drop kills.
## Columns come from the drop's own SimRng, seeded once in setup().

enum Phase { WAIT, WARN, FALL }

const SUB := SimConfig.SUB
const RADIUS := 10 * SUB
const WARN := 45
const MIN_X := 50 * SUB
const MAX_X := 310 * SUB
const TOP := SimConfig.KILL_TOP

var x := 0
var y := TOP
var phase := Phase.WAIT
## Steps left in the current phase (WAIT and WARN).
var timer := 0
## Falling speed per step.
var speed := 10 * SUB
## Steps between a drop leaving the room and the next warning.
var gap := 25
## Steps before the first warning (spreads several drops in one room).
var delay := 0

var _rng := SimRng.new()


func _init(p_delay: int = 0, p_speed: int = 10 * SUB, p_gap: int = 25) -> void:
	kind = "drop"
	delay = p_delay
	speed = p_speed
	gap = p_gap


func setup(_sim: GameSim, rng: SimRng) -> void:
	_rng.reseed(rng.next_u32())
	phase = Phase.WAIT
	timer = delay
	y = TOP


func step(_sim: GameSim) -> void:
	match phase:
		Phase.WAIT:
			timer -= 1
			if timer <= 0:
				phase = Phase.WARN
				timer = WARN
				x = MIN_X + _rng.next_below(MAX_X - MIN_X + 1)
				y = TOP
		Phase.WARN:
			timer -= 1
			if timer <= 0:
				phase = Phase.FALL
				y = TOP
		Phase.FALL:
			y += speed
			if y - RADIUS > SimConfig.WORLD_H:
				phase = Phase.WAIT
				timer = gap


func warning() -> bool:
	return phase == Phase.WARN


func falling() -> bool:
	return phase == Phase.FALL


## 0..1024 how far along the warning is (painters grow the mark or shake).
func warn_progress() -> int:
	if phase != Phase.WARN:
		return 0
	return SimTrig.ONE * (WARN - timer) / WARN


func kills(sim: GameSim) -> bool:
	return phase == Phase.FALL and sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, phase, timer, speed, gap, delay, _rng.state_checksum()])
