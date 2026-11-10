class_name ExitPlanner
extends RefCounted
## Where a room's exit portals go: the wall, the height (on a spike slot, past
## the hazards that would block the way, Hazard.blocks_exit), and at a fork a
## Calm and a Wild exit in a random order. GameSim decides when; this decides
## where. Gameplay: the RNG draws here are part of the rules.


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
		sim.state.exit_a_y = top
		sim.state.exit_b_y = bottom
		sim.state.exit_a_kind = SimState.ExitKind.CALM if calm_on_top else SimState.ExitKind.WILD
		sim.state.exit_b_kind = SimState.ExitKind.WILD if calm_on_top else SimState.ExitKind.CALM
	else:
		sim.state.exit_a_y = random_y(sim, rng, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		sim.state.exit_a_kind = SimState.ExitKind.NORMAL
		sim.state.exit_b_y = 0
		sim.state.exit_b_kind = SimState.ExitKind.NORMAL


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
		# A room with a short reach (Narrow) takes the slot nearest the bird (a
		# fork's far half has none within reach); the draw is still made.
		if sim.room.def.reach > 0:
			any = clampi(
				(sim.state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, first, last
			)
		return SimConfig.slot_center_y(any)
	return SimConfig.slot_center_y(open[rng.next_below(open.size())])


static func blocked(sim: GameSim, y: int) -> bool:
	# A room with a short reach (Narrow) keeps the exit near the bird's height.
	if sim.room.def.reach > 0 and absi(y - sim.state.y) > sim.room.def.reach:
		return true
	for h in sim.room.hazards:
		if h.alive and h.blocks_exit(sim, sim.state.exit_side, y):
			return true
	return false
