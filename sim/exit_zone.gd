class_name ExitZone
extends RefCounted
## The mouths of a room's exits, which no hazard may kill in or fill. A box
## on the exit's wall: EXIT_HALF and a bird radius above and below the exit's
## height, and three bird radii deep into the room (a bird touching the wall
## in the opening, and the last bird radius of its way in). Hazards treat the
## boxes as part of the wall: balls bounce off them, things that slide along a
## wall stop at their edge, and shots, drops and sparks break on them.
## ExitPlanner never puts an exit where a hazard is in its box already
## (ExitPlanner.blocked). Every hazard asks the same questions here. No RNG
## draws.

## How far a box reaches into the room from the wall.
const DEPTH := 3 * SimConfig.BIRD_RADIUS
## Half a box's height.
const HALF := SimConfig.EXIT_HALF + SimConfig.BIRD_RADIUS


## How many boxes there are now.
static func count(sim: GameSim) -> int:
	var s := sim.state
	if not s.exit_open and not s.exit_preview:
		return 0
	return 2 if s.exit_b_kind != SimState.ExitKind.NORMAL else 1


## The wall box `i` (below count()) is on: 0 = left, 1 = right.
static func box_side(sim: GameSim, _i: int) -> int:
	return sim.state.exit_side


## The exit height box `i` is around.
static func box_y(sim: GameSim, i: int) -> int:
	return sim.state.exit_a_y if i == 0 else sim.state.exit_b_y


## Left and right edges of a box on wall `side`.
static func left_on(sim: GameSim, side: int) -> int:
	if side == 0:
		return sim.room.wall_left()
	return sim.room.wall_right() - DEPTH


static func right_on(sim: GameSim, side: int) -> int:
	if side == 0:
		return sim.room.wall_left() + DEPTH
	return sim.room.wall_right()


## True if the box from (x0, y0) to (x1, y1) touches the box an exit at height
## `ey` on wall `side` has (edges count).
static func rect_in_box(
	sim: GameSim, side: int, ey: int, x0: int, y0: int, x1: int, y1: int
) -> bool:
	if maxi(x0, x1) < left_on(sim, side) or mini(x0, x1) > right_on(sim, side):
		return false
	return maxi(y0, y1) >= ey - HALF and mini(y0, y1) <= ey + HALF


## True if the circle at (cx, cy) with radius r touches the box an exit at
## height `ey` on wall `side` has.
static func circle_in_box(sim: GameSim, side: int, ey: int, cx: int, cy: int, r: int) -> bool:
	var nx := clampi(cx, left_on(sim, side), right_on(sim, side))
	var ny := clampi(cy, ey - HALF, ey + HALF)
	var dx := cx - nx
	var dy := cy - ny
	return dx * dx + dy * dy <= r * r


## True if the box from (x0, y0) to (x1, y1) touches any box.
static func hits_rect(sim: GameSim, x0: int, y0: int, x1: int, y1: int) -> bool:
	for i in count(sim):
		if rect_in_box(sim, box_side(sim, i), box_y(sim, i), x0, y0, x1, y1):
			return true
	return false


## True if the box from (x0, y0) to (x1, y1) touches a box on wall `side`.
static func hits_rect_on(sim: GameSim, side: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	for i in count(sim):
		if box_side(sim, i) == side and rect_in_box(sim, side, box_y(sim, i), x0, y0, x1, y1):
			return true
	return false


## The first box the circle at (cx, cy) with radius r touches, or -1.
static func circle_box(sim: GameSim, cx: int, cy: int, r: int) -> int:
	for i in count(sim):
		if circle_in_box(sim, box_side(sim, i), box_y(sim, i), cx, cy, r):
			return i
	return -1


## True if the circle at (cx, cy) with radius r touches any box.
static func hits_circle(sim: GameSim, cx: int, cy: int, r: int) -> bool:
	return circle_box(sim, cx, cy, r) >= 0


## A height for something `half` tall sliding along wall `side`: `y`, or the
## nearest height just outside a box there it would touch, between lo and hi
## (the other side of the box if the nearest is out of that range).
static func clear_y(sim: GameSim, side: int, y: int, half: int, lo: int, hi: int) -> int:
	var out := y
	for i in count(sim):
		if box_side(sim, i) != side:
			continue
		var ey := box_y(sim, i)
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
	var i := circle_box(sim, x, y, r)
	if i < 0:
		return x
	if box_side(sim, i) == 0:
		return right_on(sim, 0) + r + 1
	return left_on(sim, 1) - r - 1


## A ball of radius r at (x, y) that just moved by (vx, vy) and bounces off a
## box like off a wall. Returns [x, y, vx, vy] after the bounce, or an empty
## array if it touches no box. It came in from above or below if it was clear
## of the box's rows one step ago, else from the room side.
static func bounce(sim: GameSim, x: int, y: int, vx: int, vy: int, r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := circle_box(sim, x, y, r)
	if i < 0:
		return out
	var ey := box_y(sim, i)
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
	elif box_side(sim, i) == 0:
		var edge := right_on(sim, 0) + r + 1
		nx = 2 * edge - x
		nvx = absi(vx)
	else:
		var edge := left_on(sim, 1) - r - 1
		nx = 2 * edge - x
		nvx = -absi(vx)
	out.append_array([nx, ny, nvx, nvy])
	return out
