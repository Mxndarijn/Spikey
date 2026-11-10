extends Hazard
## Spike Belt: the side-wall spikes ride a belt. The spikes keep their slots in
## the wall mask; only their height slides (GameSim.wall_shift). A wall starts
## at rest when it gets new spikes, then slides at SPEED while the bird flies
## to it, so the gap it aims for travels about 37 px in one crossing. The belt
## holds still on a wall with an open exit (the opening never moves) and for
## the room's first ARRIVAL_BLIND steps (a player out of a portal is still
## reading the room).

## Variants (the room's variant id picks one): both belts run up; the left
## runs up and the right down; both reverse at every wall.
enum Mode { UP, COUNTER, SWITCHBACK }

## 0.45 px a step (27 px/s).
const SPEED := 29
## Never further than two slots from rest.
const MAX_SHIFT := 2 * SimConfig.SLOT_SIZE

var mode := Mode.UP
## 1 = down, -1 = up.
var left_dir := -1
var right_dir := -1
## How far each wall's spikes have slid from their slots, sub-units (+ = down).
var left_shift := 0
var right_shift := 0


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
	if not (s.exit_open and s.exit_side == 0):
		left_shift = clampi(left_shift + left_dir * SPEED, -MAX_SHIFT, MAX_SHIFT)
	if not (s.exit_open and s.exit_side == 1):
		right_shift = clampi(right_shift + right_dir * SPEED, -MAX_SHIFT, MAX_SHIFT)


## The wall the bird now flies to just got its spikes: it starts at rest.
## Switchback turns both belts round.
func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if sim.state.vx > 0:
		right_shift = 0
	else:
		left_shift = 0
	if mode == Mode.SWITCHBACK:
		left_dir = -left_dir
		right_dir = -right_dir


func wall_shift(_sim: GameSim, side: int) -> int:
	return left_shift if side == 0 else right_shift


func checksum(h: int) -> int:
	return mix_all(h, [mode, left_dir, right_dir, left_shift, right_shift])
