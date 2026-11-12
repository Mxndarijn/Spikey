extends Hazard
## Cave Tunnel, drips: a long point of the ceiling rock drips. It glints for
## GLINT steps, then a small spiked drip falls straight down from its tip to
## the floor rock at SPEED, and only the falling drip kills. When it drips is
## a timetable fixed when the room starts (`first`, then every `every` steps),
## so its place is a function of `t` alone.

const SUB := SimConfig.SUB
const RADIUS := 7 * SUB
## Steps the tip glints before the drip falls (the warning).
const GLINT := 60
## Falling speed per step.
const SPEED := 4 * SUB

## Column and the heights it falls from and to (sub-units).
var x := 0
var tip_y := 0
var floor_y := 0
## Room step of the first fall, and steps between falls.
var first := 0
var every := 0
## Now: the drip's height while it falls, and steps until the next fall while
## the tip glints (-1 when it doesn't).
var falling := false
var y := 0
var eta := -1


func _init(
	p_x: int = 0, p_tip_y: int = 0, p_floor_y: int = 0, p_first: int = 0, p_every: int = 1
) -> void:
	kind = "cave_drip"
	x = p_x
	tip_y = p_tip_y
	floor_y = p_floor_y
	first = p_first
	every = p_every
	y = tip_y


## Steps a drip falls, tip to floor.
func fall_steps() -> int:
	return (floor_y - tip_y) / SPEED + 1


func setup(_sim: GameSim, _rng: SimRng) -> void:
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	falling = false
	y = tip_y
	eta = -1
	var k := t - first
	if k < 0:
		if k >= -GLINT:
			eta = -k
		return
	var c := k % every
	if c < fall_steps():
		falling = true
		y = tip_y + c * SPEED
	elif c >= every - GLINT:
		eta = every - c


func kills(sim: GameSim) -> bool:
	return falling and sim.bird_touches_circle(x, y, RADIUS)


func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if eta < 0:
		return
	add_warning(out, x - RADIUS, tip_y, x + RADIUS, floor_y, eta, fall_steps(), WARN_KILL)


func checksum(h: int) -> int:
	return mix_all(h, [x, tip_y, floor_y, first, every, int(falling), y, eta])
