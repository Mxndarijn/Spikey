extends Hazard
## Spike Belt: the side-wall spikes ride a belt. The spikes keep their slots in
## the wall mask; only their height slides (GameSim.wall_shift). A wall starts
## at rest when it gets new spikes, then slides at SPEED while the bird flies
## to it. It never goes further than MAX_SHIFT from rest: there it turns round
## and runs back (the gap swings within two slots of where it was drawn, so
## every reach rule of the wall still holds). The exit wall holds still from
## the bounce it is drawn at once the exit is HOLD_POINTS points away (its ghost
## and opening show on it, and never get spikes slid into them). The belt
## holds still on a wall with an open exit (the opening never moves) and for
## the room's first ARRIVAL_BLIND steps (a player out of a portal is still
## reading the room).

## Variants (the room's variant id picks one): both belts run up; the left
## runs up and the right down; both reverse at every wall.
enum Mode { UP, COUNTER, SWITCHBACK }

## 0.94 px a step (56 px/s).
const SPEED := 60
## Never further than two slots from rest: the belt turns round there.
const MAX_SHIFT := 2 * SimConfig.SLOT_SIZE
## The exit wall drawn this close to the exit (points to go) holds still.
const HOLD_POINTS := 2

var mode := Mode.UP
## 1 = down, -1 = up.
var left_dir := -1
var right_dir := -1
## Each wall's turn at MAX_SHIFT: 1 runs its belt's way, -1 back. Reset when
## the wall gets new spikes.
var left_turn := 1
var right_turn := 1
## How far each wall's spikes have slid from their slots, sub-units (+ = down).
var left_shift := 0
var right_shift := 0
## Whether each wall holds still (the exit wall near the exit).
var left_hold := false
var right_hold := false


## `p_mode` -1: take it from the room's variant.
func _init(p_mode: int = -1) -> void:
	kind = "belt"
	mode = p_mode


func setup(sim: GameSim, _rng: SimRng) -> void:
	if mode < 0:
		match sim.room.variant_id():
			"counter":
				mode = Mode.COUNTER
			"switchback":
				mode = Mode.SWITCHBACK
			_:
				mode = Mode.UP
	left_dir = -1
	right_dir = 1 if mode == Mode.COUNTER else -1


func step(sim: GameSim) -> void:
	if t <= SimConfig.ARRIVAL_BLIND:
		return
	var s := sim.state
	if not left_hold and not (s.exit_open and s.exit_side == 0):
		var l := _slide(left_shift, left_dir * left_turn)
		left_shift = l[0]
		left_turn *= l[1]
	if not right_hold and not (s.exit_open and s.exit_side == 1):
		var r := _slide(right_shift, right_dir * right_turn)
		right_shift = r[0]
		right_turn *= r[1]


## One step of a belt at `shift` running `dir`: [new shift, -1 if it turned
## round at MAX_SHIFT else 1]. Past the end it bounces back the rest of the step.
static func _slide(shift: int, dir: int) -> PackedInt32Array:
	var to := shift + dir * SPEED
	if to > MAX_SHIFT:
		return PackedInt32Array([2 * MAX_SHIFT - to, -1])
	if to < -MAX_SHIFT:
		return PackedInt32Array([-2 * MAX_SHIFT - to, -1])
	return PackedInt32Array([to, 1])


## The way wall `side`'s spikes run now (1 = down, -1 = up).
func run_dir(side: int) -> int:
	return left_dir * left_turn if side == 0 else right_dir * right_turn


## A wall that just got its spikes starts at rest. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var hold := side == SimConfig.EXIT_WALL and sim.points_to_exit() <= HOLD_POINTS
	if side == 0:
		left_shift = 0
		left_turn = 1
		left_hold = hold
	else:
		right_shift = 0
		right_turn = 1
		right_hold = hold
	return mask


## Switchback turns both belts round at every bounce.
func on_bounce(_sim: GameSim, _rng: SimRng) -> void:
	if mode == Mode.SWITCHBACK:
		left_dir = -left_dir
		right_dir = -right_dir


func wall_shift(_sim: GameSim, side: int) -> int:
	return left_shift if side == 0 else right_shift


func checksum(h: int) -> int:
	return mix_all(
		h,
		[
			mode,
			left_dir,
			right_dir,
			left_shift,
			right_shift,
			int(left_hold),
			int(right_hold),
			left_turn,
			right_turn
		]
	)
