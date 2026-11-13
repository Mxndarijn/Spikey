extends Hazard
## Spike Belt: the side-wall spikes ride a belt. The spikes keep their slots in
## the wall mask; only their height slides (GameSim.wall_shift). A wall starts
## at rest when it gets new spikes, then slides at SPEED while the bird flies
## to it, so the gap it aims for travels about 37 px in the two crossings the
## wall is on view before the bird gets there. The exit wall holds still from
## the bounce it is drawn at once the exit is HOLD_POINTS points away (its ghost
## and opening show on it, and never get spikes slid into them). The belt
## holds still on a wall with an open exit (the opening never moves) and for
## the room's first ARRIVAL_BLIND steps (a player out of a portal is still
## reading the room).

## Variants (the room's variant id picks one): both belts run up; the left
## runs up and the right down; both reverse at every wall.
enum Mode { UP, COUNTER, SWITCHBACK }

## 0.23 px a step (14 px/s).
const SPEED := 15
## Never further than two slots from rest.
const MAX_SHIFT := 2 * SimConfig.SLOT_SIZE
## The exit wall drawn this close to the exit (points to go) holds still.
const HOLD_POINTS := 2

var mode := Mode.UP
## 1 = down, -1 = up.
var left_dir := -1
var right_dir := -1
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
		left_shift = clampi(left_shift + left_dir * SPEED, -MAX_SHIFT, MAX_SHIFT)
	if not right_hold and not (s.exit_open and s.exit_side == 1):
		right_shift = clampi(right_shift + right_dir * SPEED, -MAX_SHIFT, MAX_SHIFT)


## A wall that just got its spikes starts at rest. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var hold := side == SimConfig.EXIT_WALL and sim.points_to_exit() <= HOLD_POINTS
	if side == 0:
		left_shift = 0
		left_hold = hold
	else:
		right_shift = 0
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
		h, [mode, left_dir, right_dir, left_shift, right_shift, int(left_hold), int(right_hold)]
	)
