class_name ExitZone
extends RefCounted
## The mouths of a room's exits, which no hazard may kill in or fill, for the
## whole room: where its exits will be is known from the room's start
## (ExitPlanner.plan_room), on both walls, so a player who is slow or flies
## another way meets the same room. A box
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

## How many boxes a room can have (box_y() is 0 for the ones it hasn't): the
## room's planned exits (ExitPlanner.plan_room), first and fork exit on each
## wall, reserved from the room's start, and the live exit (SimState.exit_*)
## while it is open or a ghost, in case it is somewhere else (moved to the
## bird for a revive).
const BOXES := 6


static func count(_sim: GameSim) -> int:
	return BOXES


## The wall box `i` is on: 0 = left, 1 = right.
static func box_side(sim: GameSim, i: int) -> int:
	if i < 4:
		return 0 if i < 2 else 1
	return sim.state.exit_side


## The exit height box `i` is around, or 0: no such box now.
static func box_y(sim: GameSim, i: int) -> int:
	var s := sim.state
	match i:
		0:
			return s.plan_a_y_left
		1:
			return s.plan_b_y_left if s.plan_a_kind_left != SimState.ExitKind.NORMAL else 0
		2:
			return s.plan_a_y_right
		3:
			return s.plan_b_y_right if s.plan_a_kind_right != SimState.ExitKind.NORMAL else 0
	if not s.exit_open and not s.exit_preview:
		return 0
	if i == 4:
		return s.exit_a_y
	return s.exit_b_y if s.exit_b_kind != SimState.ExitKind.NORMAL else 0


## Left and right edges of a box on wall `side`.
static func left_on(sim: GameSim, side: int) -> int:
	if side == 0:
		return sim.room.wall_left()
	return sim.room.wall_right() - DEPTH


static func right_on(sim: GameSim, side: int) -> int:
	if side == 0:
		return sim.room.wall_left() + DEPTH
	return sim.room.wall_right()


## The box's x range for the touch tests: its face toward the room doesn't
## count, so something just touching it (a crate column beside it) is out.
static func _lo(sim: GameSim, side: int) -> int:
	return left_on(sim, side) + (1 if side == 1 else 0)


static func _hi(sim: GameSim, side: int) -> int:
	return right_on(sim, side) - (1 if side == 0 else 0)


## True if the box from (x0, y0) to (x1, y1) touches the box an exit at height
## `ey` on wall `side` has (edges count, but the face toward the room).
static func rect_in_box(
	sim: GameSim, side: int, ey: int, x0: int, y0: int, x1: int, y1: int
) -> bool:
	if maxi(x0, x1) < _lo(sim, side) or mini(x0, x1) > _hi(sim, side):
		return false
	return maxi(y0, y1) >= ey - HALF and mini(y0, y1) <= ey + HALF


## True if the circle at (cx, cy) with radius r touches the box an exit at
## height `ey` on wall `side` has.
static func circle_in_box(sim: GameSim, side: int, ey: int, cx: int, cy: int, r: int) -> bool:
	var nx := clampi(cx, _lo(sim, side), _hi(sim, side))
	var ny := clampi(cy, ey - HALF, ey + HALF)
	var dx := cx - nx
	var dy := cy - ny
	return dx * dx + dy * dy <= r * r


## True if the box from (x0, y0) to (x1, y1) touches any box.
static func hits_rect(sim: GameSim, x0: int, y0: int, x1: int, y1: int) -> bool:
	for i in BOXES:
		var ey := box_y(sim, i)
		if ey != 0 and rect_in_box(sim, box_side(sim, i), ey, x0, y0, x1, y1):
			return true
	return false


## True if the box from (x0, y0) to (x1, y1) touches a box on wall `side`.
static func hits_rect_on(sim: GameSim, side: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	for i in BOXES:
		var ey := box_y(sim, i)
		if ey != 0 and box_side(sim, i) == side and rect_in_box(sim, side, ey, x0, y0, x1, y1):
			return true
	return false


## The first box the circle at (cx, cy) with radius r touches, or -1.
static func circle_box(sim: GameSim, cx: int, cy: int, r: int) -> int:
	for i in BOXES:
		var ey := box_y(sim, i)
		if ey != 0 and circle_in_box(sim, box_side(sim, i), ey, cx, cy, r):
			return i
	return -1


## True if the circle at (cx, cy) with radius r touches any box.
static func hits_circle(sim: GameSim, cx: int, cy: int, r: int) -> bool:
	return circle_box(sim, cx, cy, r) >= 0


## A height for something `half` tall sliding along wall `side` (-1: either
## wall, for a pair of things level on both): `y`, or the
## nearest height just outside the boxes there it would touch (past two close
## boxes at once), between lo and hi (the other way if the nearest is out of
## that range).
static func clear_y(sim: GameSim, side: int, y: int, half: int, lo: int, hi: int) -> int:
	var reach := HALF + half + 1
	var first := -1
	for i in BOXES:
		var ey := box_y(sim, i)
		if ey != 0 and _on(sim, i, side) and absi(y - ey) < reach:
			first = i
			break
	if first < 0:
		return y
	var dir := -1 if y < box_y(sim, first) else 1
	var out := _push_y(sim, side, y, reach, dir)
	if out < lo or out > hi:
		out = _push_y(sim, side, y, reach, -dir)
	return out


## `y` pushed `dir` (-1 up, 1 down) until it is `reach` or more from every
## box on wall `side`.
static func _push_y(sim: GameSim, side: int, y: int, reach: int, dir: int) -> int:
	var out := y
	for k in BOXES:
		var moved := false
		for i in BOXES:
			var ey := box_y(sim, i)
			if ey != 0 and _on(sim, i, side) and absi(out - ey) < reach:
				out = ey + dir * reach
				moved = true
		if not moved:
			break
	return out


## Something `half` tall sliding along wall `side` from `from` to `to`: `to`,
## or, if that is in a box, the box's edge on the `from` side (it stops there,
## it never jumps a box). From inside a box (it was put there before the box
## was known) it jumps out, as clear_y().
static func stop_y(sim: GameSim, side: int, from: int, to: int, half: int, lo: int, hi: int) -> int:
	var reach := HALF + half + 1
	if clear_y(sim, side, from, half, lo, hi) != from:
		return clear_y(sim, side, to, half, lo, hi)
	if to == from:
		return to
	return _push_y(sim, side, to, reach, -1 if to > from else 1)


static func _on(sim: GameSim, i: int, side: int) -> bool:
	return side < 0 or box_side(sim, i) == side


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
