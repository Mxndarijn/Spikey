extends Hazard
## New Year Firework Burst: a rocket waits on the floor (the warning, safe),
## climbs straight up and bursts at a height into eight sparks that fly out in
## a ring and fade. The climbing rocket and the bright sparks kill; fading
## sparks do not. Column and burst height come from its own SimRng (seeded in
## setup()), redrawn for every launch.
##
## Styles (Firework Burst variants): RING as above; DOUBLE bursts a second ring
## ECHO steps after the first, turned half a spark so it fills the gaps; CROSS
## throws four arms of three sparks (up, down, left, right) instead of a ring.

enum Phase { PAD, CLIMB, BURST, REST }
enum Style { RING, DOUBLE, CROSS }

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
## DOUBLE: steps between the two bursts.
const ECHO := 16
## CROSS: arms and sparks on each arm.
const ARMS := 4
const ARM_SPARKS := 3
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
var style: int = Style.RING
var _rng := SimRng.new()


func _init(p_delay: int = 0, p_style: int = Style.RING) -> void:
	kind = "firework"
	delay = p_delay
	style = p_style


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
			if timer >= burst_steps():
				phase = Phase.REST
				timer = REST
		Phase.REST:
			timer -= 1
			if timer <= 0:
				_load()


## Steps the burst lasts (DOUBLE: until the second ring has faded).
func burst_steps() -> int:
	return BURST + ECHO if style == Style.DOUBLE else BURST


func spark_count() -> int:
	match style:
		Style.DOUBLE:
			return 2 * SPARKS
		Style.CROSS:
			return ARMS * ARM_SPARKS
	return SPARKS


## Steps into the burst spark `i` started flying (DOUBLE: the second ring later).
func spark_start(i: int) -> int:
	return ECHO if style == Style.DOUBLE and i >= SPARKS else 0


## Steps spark `i` has flown so far (negative: not out yet).
func spark_age(i: int) -> int:
	return timer - spark_start(i)


## 0..1024 how bright the sparks are (they fade after SPARK_DEADLY).
func spark_alpha() -> int:
	return spark_alpha_of(0)


## 0..1024 how bright spark `i` is (0 before it is out and once it is gone).
func spark_alpha_of(i: int) -> int:
	var age := spark_age(i)
	if phase != Phase.BURST or age < 0:
		return 0
	if age < SPARK_DEADLY:
		return SimTrig.ONE
	return maxi(0, SimTrig.ONE * (BURST - age) / (BURST - SPARK_DEADLY))


## Whether spark `i` is out and still bright (it kills).
func spark_live(i: int) -> bool:
	var age := spark_age(i)
	return phase == Phase.BURST and age >= 0 and age < SPARK_DEADLY


## SimTrig angle spark `i` flies at.
func spark_angle(i: int) -> int:
	match style:
		Style.DOUBLE:
			return (2 * (i % SPARKS) + (1 if i >= SPARKS else 0)) * SimTrig.TURN / (2 * SPARKS)
		Style.CROSS:
			return (i / ARM_SPARKS) * SimTrig.TURN / ARMS
	return i * SimTrig.TURN / SPARKS


## How far spark `i` is from the burst point.
func spark_dist(i: int) -> int:
	match style:
		Style.DOUBLE:
			return maxi(0, spark_age(i)) * SPARK_SPEED
		Style.CROSS:
			return spread * (i % ARM_SPARKS + 1) / ARM_SPARKS
	return spread


## 0..1024 how far along the pad wait is (the painter's fuse).
func fuse_progress() -> int:
	if phase != Phase.PAD:
		return 0
	return SimTrig.ONE - SimTrig.ONE * mini(timer, PAD) / PAD


func spark_x(i: int) -> int:
	return x + spark_dist(i) * SimTrig.cos_t(spark_angle(i)) / SimTrig.ONE


func spark_y(i: int) -> int:
	return y + spark_dist(i) * SimTrig.sin_t(spark_angle(i)) / SimTrig.ONE


func kills(sim: GameSim) -> bool:
	if phase == Phase.CLIMB:
		return sim.bird_touches_circle(x, y, ROCKET_RADIUS)
	if phase == Phase.BURST:
		for i in spark_count():
			if spark_live(i) and sim.bird_touches_circle(spark_x(i), spark_y(i), SPARK_RADIUS):
				return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(h, [x, y, burst_y, phase, timer, spread, delay, _rng.state_checksum()])
	if style != Style.RING:
		out = mix_all(out, [style])
	return out
