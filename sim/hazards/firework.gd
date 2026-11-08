extends Hazard
## New Year Firework Burst: a rocket waits on the floor (the warning, safe),
## climbs straight up and bursts at a height into eight sparks that fly out in
## a ring and fade. The climbing rocket and the bright sparks kill; fading
## sparks do not. Column and burst height come from its own SimRng (seeded in
## setup()), redrawn for every launch.

enum Phase { PAD, CLIMB, BURST, REST }

const SUB := SimConfig.SUB
const ROCKET_RADIUS := 8 * SUB
const SPARK_RADIUS := 6 * SUB
const SPARKS := 8
## Steps the rocket sits on the floor before launch.
const PAD := 60
const CLIMB_VY := 8 * SUB
const SPARK_SPEED := 4 * SUB
## Sparks fly for BURST steps and kill for the first SPARK_DEADLY of them.
const BURST := 44
const SPARK_DEADLY := 30
const REST := 20
const MIN_X := 80 * SUB
const MAX_X := 280 * SUB
const MIN_BURST_Y := 170 * SUB
const MAX_BURST_Y := 380 * SUB
const PAD_Y := SimConfig.KILL_BOTTOM - ROCKET_RADIUS

var x := 0
var y := PAD_Y
var burst_y := 0
var phase := Phase.PAD
var timer := 0
## Distance the sparks have flown from the burst point.
var spread := 0
## Extra steps on the pad before the first launch.
var delay := 0
var _rng := SimRng.new()


func _init(p_delay: int = 0) -> void:
	kind = "firework"
	delay = p_delay


func setup(_sim: GameSim, rng: SimRng) -> void:
	_rng.reseed(rng.next_u32())
	_load()
	timer += delay


## A new rocket on the pad, in a new column with a new burst height.
func _load() -> void:
	phase = Phase.PAD
	timer = PAD
	spread = 0
	x = MIN_X + _rng.next_below(MAX_X - MIN_X + 1)
	burst_y = MIN_BURST_Y + _rng.next_below(MAX_BURST_Y - MIN_BURST_Y + 1)
	y = PAD_Y


func step(_sim: GameSim) -> void:
	match phase:
		Phase.PAD:
			timer -= 1
			if timer <= 0:
				phase = Phase.CLIMB
		Phase.CLIMB:
			y -= CLIMB_VY
			if y <= burst_y:
				y = burst_y
				phase = Phase.BURST
				timer = 0
				spread = 0
		Phase.BURST:
			timer += 1
			spread += SPARK_SPEED
			if timer >= BURST:
				phase = Phase.REST
				timer = REST
		Phase.REST:
			timer -= 1
			if timer <= 0:
				_load()


## 0..1024 how bright the sparks are (they fade after SPARK_DEADLY).
func spark_alpha() -> int:
	if phase != Phase.BURST:
		return 0
	if timer < SPARK_DEADLY:
		return SimTrig.ONE
	return SimTrig.ONE * (BURST - timer) / (BURST - SPARK_DEADLY)


## 0..1024 how far along the pad wait is (the painter's fuse).
func fuse_progress() -> int:
	if phase != Phase.PAD:
		return 0
	return SimTrig.ONE - SimTrig.ONE * mini(timer, PAD) / PAD


func spark_x(i: int) -> int:
	return x + spread * SimTrig.cos_t(i * SimTrig.TURN / SPARKS) / SimTrig.ONE


func spark_y(i: int) -> int:
	return y + spread * SimTrig.sin_t(i * SimTrig.TURN / SPARKS) / SimTrig.ONE


func kills(sim: GameSim) -> bool:
	if phase == Phase.CLIMB:
		return sim.bird_touches_circle(x, y, ROCKET_RADIUS)
	if phase == Phase.BURST and timer < SPARK_DEADLY:
		for i in SPARKS:
			if sim.bird_touches_circle(spark_x(i), spark_y(i), SPARK_RADIUS):
				return true
	return false


func checksum(h: int) -> int:
	return mix_all(h, [x, y, burst_y, phase, timer, spread, delay, _rng.state_checksum()])
