class_name ExitZone
extends RefCounted
## The mouth of an open or ghost exit, which no hazard may kill in or fill.
## A box on the exit's wall: EXIT_HALF and a bird radius above and below the
## exit's height, and three bird radii deep into the room (a bird touching the
## wall in the opening, and the last bird radius of its way in). While an exit
## is open or shown as a ghost, hazards treat this box as part of the wall:
## balls bounce off it, things that slide along a wall stop at its edge, and
## shots, drops and sparks break on it. ExitPlanner never puts an exit where a
## hazard is in the box already (ExitPlanner.blocked). Every hazard asks the
## same questions here. No RNG draws.

## How far the box reaches into the room from the wall.
const DEPTH := 3 * SimConfig.BIRD_RADIUS
## Half the box's height.
const HALF := SimConfig.EXIT_HALF + SimConfig.BIRD_RADIUS


## How many exits have a box now: 0 (none open or shown), 1, or 2 at a fork.
static func count(sim: GameSim) -> int:
	var s := sim.state
	if not s.exit_open and not s.exit_preview:
		return 0
	return 2 if s.exit_b_kind != SimState.ExitKind.NORMAL else 1


## The height of exit `i` (0 or 1, below count()).
static func exit_y(sim: GameSim, i: int) -> int:
	return sim.state.exit_a_y if i == 0 else sim.state.exit_b_y


## The wall the boxes are on (0 = left, 1 = right).
static func side(sim: GameSim) -> int:
	return sim.state.exit_side


## Left and right edges of the boxes.
static func left(sim: GameSim) -> int:
	return left_on(sim, sim.state.exit_side)


static func right(sim: GameSim) -> int:
	return right_on(sim, sim.state.exit_side)


## Left and right edges of a box on wall `p_side`.
static func left_on(sim: GameSim, p_side: int) -> int:
	if p_side == 0:
		return sim.room.wall_left()
	return sim.room.wall_right() - DEPTH


static func right_on(sim: GameSim, p_side: int) -> int:
	if p_side == 0:
		return sim.room.wall_left() + DEPTH
	return sim.room.wall_right()


## True if the box from (x0, y0) to (x1, y1) touches the box an exit at height
## `ey` on wall `p_side` would have (for Hazard.blocks_exit, before it is there).
static func rect_in_box(
	sim: GameSim, p_side: int, ey: int, x0: int, y0: int, x1: int, y1: int
) -> bool:
	if maxi(x0, x1) < left_on(sim, p_side) or mini(x0, x1) > right_on(sim, p_side):
		return false
	return maxi(y0, y1) >= ey - HALF and mini(y0, y1) <= ey + HALF


## The edge of the boxes that faces the room.
static func inner_x(sim: GameSim) -> int:
	return right(sim) if sim.state.exit_side == 0 else left(sim)


## True if the box from (x0, y0) to (x1, y1) touches a box (edges count).
static func hits_rect(sim: GameSim, x0: int, y0: int, x1: int, y1: int) -> bool:
	for i in count(sim):
		if rect_in_box(sim, sim.state.exit_side, exit_y(sim, i), x0, y0, x1, y1):
			return true
	return false


## The box `cy` is in or nearest to, or -1 with no exit (for a circle at cy).
static func _nearest(sim: GameSim, cy: int) -> int:
	var n := count(sim)
	if n == 0:
		return -1
	if n == 1:
		return 0
	return 0 if absi(cy - exit_y(sim, 0)) <= absi(cy - exit_y(sim, 1)) else 1


## True if the circle at (cx, cy) with radius r touches a box.
static func hits_circle(sim: GameSim, cx: int, cy: int, r: int) -> bool:
	for i in count(sim):
		if circle_in_box(sim, sim.state.exit_side, exit_y(sim, i), cx, cy, r):
			return true
	return false


## True if the circle at (cx, cy) with radius r touches the box an exit at
## height `ey` on wall `p_side` would have.
static func circle_in_box(sim: GameSim, p_side: int, ey: int, cx: int, cy: int, r: int) -> bool:
	var nx := clampi(cx, left_on(sim, p_side), right_on(sim, p_side))
	var ny := clampi(cy, ey - HALF, ey + HALF)
	var dx := cx - nx
	var dy := cy - ny
	return dx * dx + dy * dy <= r * r


## A height for something `half` tall sliding along the exit's wall: `y`, or
## the nearest height just outside the box it would touch, between lo and hi
## (the other side of the box if the nearest is out of that range).
static func clear_y(sim: GameSim, y: int, half: int, lo: int, hi: int) -> int:
	var out := y
	for i in count(sim):
		var ey := exit_y(sim, i)
		var reach := HALF + half + 1
		if absi(out - ey) >= reach:
			continue
		var up := ey - reach
		var down := ey + reach
		if out < ey:
			out = up if up >= lo else down
		else:
			out = down if down <= hi else up
	return out


## A circle of radius r at (x, y) moved straight out of the room-facing side
## of a box it touches; x unchanged if it touches none.
static func push_x(sim: GameSim, x: int, y: int, r: int) -> int:
	if not hits_circle(sim, x, y, r):
		return x
	if sim.state.exit_side == 0:
		return right(sim) + r + 1
	return left(sim) - r - 1


## A ball of radius r at (x, y) that just moved by (vx, vy) and bounces off a
## box like off a wall. Returns [x, y, vx, vy] after the bounce, or an empty
## array if it touches no box. It came in from above or below if it was clear
## of the box's rows one step ago, else from the room side.
static func bounce(sim: GameSim, x: int, y: int, vx: int, vy: int, r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not hits_circle(sim, x, y, r):
		return out
	var ey := exit_y(sim, _nearest(sim, y))
	var prev_y := y - vy
	var nx := x
	var ny := y
	var nvx := vx
	var nvy := vy
	if prev_y + r < ey - HALF:
		var top := ey - HALF - r - 1
		ny = 2 * top - y
		nvy = -absi(vy)
	elif prev_y - r > ey + HALF:
		var bottom := ey + HALF + r + 1
		ny = 2 * bottom - y
		nvy = absi(vy)
	elif sim.state.exit_side == 0:
		var edge := right(sim) + r + 1
		nx = 2 * edge - x
		nvx = absi(vx)
	else:
		var edge := left(sim) - r - 1
		nx = 2 * edge - x
		nvx = -absi(vx)
	out.append_array([nx, ny, nvx, nvy])
	return out
