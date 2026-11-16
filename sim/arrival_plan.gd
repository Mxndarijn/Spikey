class_name ArrivalPlan
extends RefCounted
## Speed only, not gameplay: a portal arrival's check (GameSim._arrival_retries,
## up to hundreds of layouts played on copies) worked out ahead, so the portal
## tick doesn't play it. The game plans on a copy on a worker thread while the
## bird flies to the open exit (ArrivalAhead) and offers the result; the
## arrival takes it only when its key is the arrival's own exact inputs, else
## it checks as before. The same room comes out either way. Not in the checksum;
## FastSim-RS has no copy of this (its bots memo the check: arrival_memo.rs).
## A plan: [key, retries, unpin, band, unfit].


## On a copy of the sim (SimCopy.copy; it is used up): goes through the exit on
## wall `side` as GameSim._take_exit would (`kind`, `through_y`) and plays the
## arrival check there. Returns the plan, for offer() on the real sim.
static func plan(copy: GameSim, side: int, kind: int, through_y: int) -> Array:
	copy._arrival_offers = []
	var next := copy._through_door(kind, through_y)
	var k := key(copy, side, next)
	var retries := copy._arrival_retries(side, next)
	return [k, retries, copy._arrival_unpin, copy._arrival_band, copy._arrival_unfit]


## Hands the sim plans (one per open exit). The next portal arrival takes the
## one with its own key, if any; then all are dropped.
static func offer(sim: GameSim, plans: Array) -> void:
	sim._arrival_offers = plans.duplicate()


## Whether the last portal arrival took an offered plan (tools and tests).
static func taken(sim: GameSim) -> bool:
	return sim._arrival_planned


## From GameSim._arrival_retries: an offered plan's retries when one has this
## arrival's key (its flags set on the sim), else -1. Drops the offers.
static func take(sim: GameSim, side: int, next: int) -> int:
	if sim._arrival_offers.is_empty():
		return -1
	var offers := sim._arrival_offers
	sim._arrival_offers = []
	var k := key(sim, side, next)
	for p: Array in offers:
		if p[0] == k:
			sim._arrival_unpin = p[2]
			sim._arrival_band = p[3]
			sim._arrival_unfit = p[4]
			sim._arrival_planned = true
			return p[1]
	return -1


## Every input of _arrival_retries(side, next) once _through_door has run: the
## state but the bird's own motion and the tick and flap counts (each layout is
## tried with the bird at the portal, flying level, at every ARRIVAL_HEIGHTS
## height, and nothing reads the counts), the run's settings, the wall run, the
## free wall part, the planner's overrides, both RNGs and the room seed.
## tests/unit/test_arrival_ahead.gd keeps it complete.
static func key(sim: GameSim, side: int, next: int) -> Array:
	var out := [
		side,
		next,
		sim.seed_value,
		sim.season,
		sim.practice_room,
		sim.forced_variant,
		sim.wall_run.duplicate(),
		sim.room.rng_seed,
		sim._free_lo,
		sim._free_hi,
		sim._points_override,
		sim._points_also,
	]
	out.append_array(sim._rng.key())
	out.append_array(sim._spine.key())
	out.append_array(sim.state.arrival_key())
	return out
