class_name ExitPlanner
extends RefCounted
## Where a room's exit portals go: the wall, the height (on a spike slot, past
## the hazards that would block the way, Hazard.blocks_exit), and at a fork a
## Calm and a Wild exit in a random order. GameSim decides when; this decides
## where. Gameplay: the RNG draws here are part of the rules.
##
## The exits are picked once, when the room starts (plan_room), from the
## room's own RNG: one for each wall, for the next exit score. The ghost and
## the open exit then only show them (use_plan), so every player of a seed
## meets the same exits, however and whenever they fly, and hazards keep out
## of their zone (reserved) for the whole room.

## A fork's two exits stay this far apart (centre to centre): both portals and
## the spike-free gaps around them fit.
const FORK_APART := 3 * SimConfig.SLOT_SIZE
## Salt for the RNG plan_room draws from (seeded from the room's seed).
const PLAN_SALT := 0x45584954

## Height step of the bird circles in_mouth() tries.
const MOUTH_STEP := 4 * SimConfig.SUB


## Wall slots that overlap the open (or ghost) exit(s), so no spike sits in one.
static func slots(state: SimState) -> int:
	var out := 0
	var reach := SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE
	for slot in SimConfig.SLOT_COUNT:
		var cy := SimConfig.slot_center_y(slot)
		if absi(cy - state.exit_a_y) < reach:
			out |= 1 << slot
		if state.exit_b_kind != SimState.ExitKind.NORMAL and absi(cy - state.exit_b_y) < reach:
			out |= 1 << slot
	return out


## Picks where the exit(s) for score `at` go, on wall `side`.
static func plan(sim: GameSim, rng: SimRng, side: int, at: int) -> void:
	sim.state.exit_side = side
	var fork := at % SimConfig.FORK_EVERY == 0 and not sim.is_practice()
	if fork:
		var top := random_y(
			sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.FORK_SPLIT_Y - SimConfig.EXIT_HALF
		)
		var bottom := random_y(
			sim, rng, SimConfig.FORK_SPLIT_Y + SimConfig.EXIT_HALF, SimConfig.EXIT_MAX_Y
		)
		var calm_on_top := rng.next_below(2) == 0
		# A half its hazards block all of (Lava Rise near its top) gets the
		# free slot nearest it anywhere on the wall, clear of the other exit.
		if blocked(sim, bottom):
			bottom = _free_apart(sim, bottom, top)
		if blocked(sim, top):
			top = _free_apart(sim, top, bottom)
		sim.state.exit_a_y = top
		sim.state.exit_b_y = bottom
		sim.state.exit_a_kind = SimState.ExitKind.CALM if calm_on_top else SimState.ExitKind.WILD
		sim.state.exit_b_kind = SimState.ExitKind.WILD if calm_on_top else SimState.ExitKind.CALM
	else:
		sim.state.exit_a_y = random_y(sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		sim.state.exit_a_kind = SimState.ExitKind.NORMAL
		sim.state.exit_b_y = 0
		sim.state.exit_b_kind = SimState.ExitKind.NORMAL


## Picks the room's exits for both walls (see the top): wall 0 first, then
## wall 1, each as plan() would for exit score `at`. The live exit
## (SimState.exit_*) is left as it was.
static func plan_room(sim: GameSim, at: int) -> void:
	var s := sim.state
	var rng := SimRng.new(SimHash.mix(sim.room.rng_seed, PLAN_SALT))
	var keep := [s.exit_side, s.exit_a_y, s.exit_a_kind, s.exit_b_y, s.exit_b_kind]
	s.plan_at = at
	# No boxes while planning: hazards asked here (ExitZone) must not see the
	# last room's.
	s.plan_a_y_left = 0
	s.plan_b_y_left = 0
	s.plan_a_y_right = 0
	s.plan_b_y_right = 0
	# A revive brings the bird back out of its portal with one point (or
	# none) to go, and puts the exit on the wall behind it: that wall's exit
	# must also be clear for the bird getting there a crossing after the
	# portal (GameSim.revive).
	var heading := 1 if s.vx > 0 else 0
	for side in 2:
		sim._points_also = 1 if side != heading else -1
		plan(sim, rng, side, at)
		sim._points_also = -1
		if side == 0:
			s.plan_a_y_left = s.exit_a_y
			s.plan_a_kind_left = s.exit_a_kind
			s.plan_b_y_left = s.exit_b_y
		else:
			s.plan_a_y_right = s.exit_a_y
			s.plan_a_kind_right = s.exit_a_kind
			s.plan_b_y_right = s.exit_b_y
	s.exit_side = keep[0]
	s.exit_a_y = keep[1]
	s.exit_a_kind = keep[2]
	s.exit_b_y = keep[3]
	s.exit_b_kind = keep[4]


## Puts the room's planned exit(s) for wall `side` (plan_room) on that wall,
## as the ghost or the open exit for score `at`. A plan for another score
## (only when a test or tool set the score by hand) is made again first.
static func use_plan(sim: GameSim, side: int, at: int) -> void:
	var s := sim.state
	if s.plan_at != at:
		plan_room(sim, at)
	s.exit_side = side
	s.exit_a_y = s.plan_a_y_left if side == 0 else s.plan_a_y_right
	s.exit_a_kind = s.plan_a_kind_left if side == 0 else s.plan_a_kind_right
	s.exit_b_y = s.plan_b_y_left if side == 0 else s.plan_b_y_right
	s.exit_b_kind = _other_kind(s.exit_a_kind)


## The planned exit height on wall `side` nearest `y` (at a fork, of the two).
static func planned_y(sim: GameSim, side: int, y: int) -> int:
	var s := sim.state
	var a := s.plan_a_y_left if side == 0 else s.plan_a_y_right
	var kind := s.plan_a_kind_left if side == 0 else s.plan_a_kind_right
	var b := s.plan_b_y_left if side == 0 else s.plan_b_y_right
	if kind != SimState.ExitKind.NORMAL and absi(b - y) < absi(a - y):
		return b
	return a


## Whether height `y` on wall `side` is in one of the room's planned exits (a
## spike slot's reach around its portal): hazards keep out of it all room.
static func reserved(sim: GameSim, side: int, y: int) -> bool:
	var s := sim.state
	var reach := SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE
	var a := s.plan_a_y_left if side == 0 else s.plan_a_y_right
	var kind := s.plan_a_kind_left if side == 0 else s.plan_a_kind_right
	var b := s.plan_b_y_left if side == 0 else s.plan_b_y_right
	if absi(y - a) < reach:
		return true
	return kind != SimState.ExitKind.NORMAL and absi(y - b) < reach


## The slot from `first` to `last` nearest one an exit could take anywhere
## on the wall (not blocked): when hazards block a whole half at a fork, its
## exit still goes as near the way through as it can. `fallback` if no slot
## on the wall is free.
static func _nearest_free(sim: GameSim, first: int, last: int, fallback: int) -> int:
	var c0 := SimConfig.slot_center_y(0)
	var lo := (SimConfig.EXIT_MIN_Y - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE
	var hi := (SimConfig.EXIT_MAX_Y - c0) / SimConfig.SLOT_SIZE
	var best := fallback
	var best_d := -1
	for slot in range(lo, hi + 1):
		if blocked(sim, SimConfig.slot_center_y(slot)):
			continue
		var near := clampi(slot, first, last)
		var d := absi(slot - near)
		if best_d < 0 or d < best_d:
			best = near
			best_d = d
	return best


## The free exit height nearest `y` on the whole wall at least FORK_APART from
## `other` (the fork's other exit), or `y` if there is none.
static func _free_apart(sim: GameSim, y: int, other: int) -> int:
	var c0 := SimConfig.slot_center_y(0)
	var lo := (SimConfig.EXIT_MIN_Y - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE
	var hi := (SimConfig.EXIT_MAX_Y - c0) / SimConfig.SLOT_SIZE
	var best := y
	var best_d := -1
	for slot in range(lo, hi + 1):
		var cy := SimConfig.slot_center_y(slot)
		if absi(cy - other) < FORK_APART or blocked(sim, cy):
			continue
		var d := absi(cy - y)
		if best_d < 0 or d < best_d:
			best = cy
			best_d = d
	return best


static func _other_kind(kind: int) -> int:
	if kind == SimState.ExitKind.CALM:
		return SimState.ExitKind.WILD
	if kind == SimState.ExitKind.WILD:
		return SimState.ExitKind.CALM
	return SimState.ExitKind.NORMAL


## A random exit height between lo and hi, on a spike slot's center. The
## opening is then always that slot and one either side, with the portal in
## the middle of it, so the gap is the same everywhere.
static func random_y(sim: GameSim, rng: SimRng, lo: int, hi: int) -> int:
	var c0 := SimConfig.slot_center_y(0)
	var first := (lo - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE
	var last := (hi - c0) / SimConfig.SLOT_SIZE
	# Slots no hazard blocks (Hazard.blocks_exit). One draw either way; if all
	# are blocked, any slot will have to do.
	var open: Array[int] = []
	for slot in range(first, last + 1):
		if not blocked(sim, SimConfig.slot_center_y(slot)):
			open.append(slot)
	if open.is_empty():
		var any := first + rng.next_below(last - first + 1)
		# A room with a short reach (Narrow) takes the slot nearest the anchor
		# (a fork's far half has none within reach); the draw is still made.
		if sim.room.def.reach > 0:
			any = clampi(
				(sim.state.anchor_y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE,
				first,
				last
			)
		else:
			any = _nearest_free(sim, first, last, any)
		return SimConfig.slot_center_y(any)
	return SimConfig.slot_center_y(open[rng.next_below(open.size())])


static func blocked(sim: GameSim, y: int) -> bool:
	if _blocked_now(sim, y):
		return true
	if sim._points_also < 0:
		return false
	var keep := sim._points_override
	sim._points_override = sim._points_also
	var out := _blocked_now(sim, y)
	sim._points_override = keep
	return out


static func _blocked_now(sim: GameSim, y: int) -> bool:
	# A room with a short reach (Narrow) keeps the exit near the anchor (where
	# generation puts the bird, SimState.anchor_y).
	if sim.room.def.reach > 0 and absi(y - sim.state.anchor_y) > sim.room.def.reach:
		return true
	for h in sim.room.hazards:
		if h.alive and h.blocks_exit(sim, sim.state.exit_side, y):
			return true
	return in_mouth(sim, sim.state.exit_side, y)


## True if a hazard kills a bird anywhere in the mouth of an exit at height `y`
## on wall `side` right now: touching the wall within EXIT_HALF of `y`, or up
## to a bird radius in front of that (ExitZone's box). Hazards keep out of an
## open exit's box once it is there; this keeps an exit from being put where
## one already is. No RNG draws.
static func in_mouth(sim: GameSim, side: int, y: int) -> bool:
	var s := sim.state
	var r := SimConfig.BIRD_RADIUS
	var keep_x := s.x
	var keep_y := s.y
	var wall := sim.room.wall_left() + r if side == 0 else sim.room.wall_right() - r
	var dir := 1 if side == 0 else -1
	var out := false
	for dx: int in [0, r / 2, r - 1]:
		var dy := -SimConfig.EXIT_HALF
		while dy <= SimConfig.EXIT_HALF and not out:
			s.x = wall + dir * dx
			s.y = y + dy
			for h in sim.room.hazards:
				if h.alive and h.kills(sim):
					out = true
					break
			dy += MOUTH_STEP
		if out:
			break
	s.x = keep_x
	s.y = keep_y
	return out
