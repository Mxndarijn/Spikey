class_name VariantCheck
extends RefCounted
## The fairness check every GENERATED variant's layout passes (RoomRuntime
## retries with the next draws until one does, then builds the recipe's safe
## fallback). Out of a portal a bird anywhere in the exit it came through
## (GameSim.ARRIVAL_HEIGHTS around the PLANNED height, SimState.anchor_y) that
## only holds its height for HOLD_STEPS moving steps (the reading time: the
## room is frozen during the portal hold) touches nothing deadly and is not
## pushed into the ceiling or floor (what the hazards do to it, touch(), acts on
## it: air lifts it, a bubble carries it). The way on
## from there is ArrivalCheck's (GameSim._arrival_retries), the exits are
## ExitPlanner's (blocks_exit) and the warnings are the hazards' own, as for
## every room. Plays copies only: no RNG draws, the room is left as it is.

## Moving steps the bird only holds its height (SimConfig.ARRIVAL_BLIND: a
## second of flight: out of a portal the bird flies on at once).
const HOLD_STEPS := SimConfig.ARRIVAL_BLIND


## Whether the room as built so far is fair out of a portal (always true at
## the start of a run: the start lane rules keep that). `avoid_touch`: the
## bird may not even touch a bubble (one could carry it up into the ceiling).
## `steps`: how long it holds (0 = HOLD_STEPS).
static func holds(sim: GameSim, avoid_touch: bool = false, steps: int = 0) -> bool:
	if not sim.state.started:
		return true
	var n := steps if steps > 0 else HOLD_STEPS
	for dy: int in GameSim.ARRIVAL_HEIGHTS:
		var at := GameSim._arrival_y(sim.state.anchor_y + arrival_dy(sim, dy))
		if not _holds_at(sim, at, avoid_touch, n):
			return false
	return true


## Arrival height `dy` (one of GameSim.ARRIVAL_HEIGHTS) scaled to the room
## variant's arrival_spread: where the arrival checks put the bird in it.
static func arrival_dy(sim: GameSim, dy: int) -> int:
	var room := sim.room
	if room.def.variants.is_empty() or room.def.variants[room.variant].arrival_spread == 0:
		return dy
	return dy * room.def.variants[room.variant].arrival_spread / SimConfig.EXIT_FIT


## The hazard (its index in the room) that first hits a bird holding its
## height out of the exit (as holds() flies them, every height in turn), -2 if
## the ceiling or floor does, -1 if none: a recipe leaves out what is in the
## bird's way (Ghost Doors).
static func first_hit(sim: GameSim, steps: int = 0) -> int:
	if not sim.state.started:
		return -1
	var n := steps if steps > 0 else HOLD_STEPS
	for dy: int in GameSim.ARRIVAL_HEIGHTS:
		var at := GameSim._arrival_y(sim.state.anchor_y + arrival_dy(sim, dy))
		var hit := _hit_at(sim, at, false, n)
		if hit != -1:
			return hit
	return -1


## One bird holding height `hold`, as FairLanes.arrival_path flies it.
static func _holds_at(sim: GameSim, hold: int, avoid_touch: bool, steps: int) -> bool:
	return _hit_at(sim, hold, avoid_touch, steps) == -1


## What first hits it (first_hit), or -1.
static func _hit_at(sim: GameSim, hold: int, avoid_touch: bool, steps: int) -> int:
	var c := SimCopy.copy(sim)
	var g := c.room.gravity
	var y := hold
	var vy := 0
	c.state.y = y
	c.state.vy = 0
	for k in steps:
		c.room.step(c)
		if (y - hold) * g > 0 and vy * g >= 0:
			vy = SimConfig.FLAP_VY * g
		vy = clampi(vy + SimConfig.GRAVITY * g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)
		y += vy
		c.state.x = FairLanes.arrival_x(sim, k + 1)
		c.state.y = y
		c.state.vy = vy
		for h in c.room.hazards:
			if h.alive:
				h.touch(c)
		y = c.state.y
		vy = c.state.vy
		var r := SimConfig.BIRD_RADIUS
		if y - r <= SimConfig.KILL_TOP or y + r >= SimConfig.KILL_BOTTOM:
			return -2
		for i in c.room.hazards.size():
			var h: Hazard = c.room.hazards[i]
			if not h.alive:
				continue
			if h.kills(c) or (avoid_touch and _touches(c, h)):
				return i
	return -1


## Whether the bird touches a bubble's body.
static func _touches(sim: GameSim, h: Hazard) -> bool:
	if h.kind != "bubble":
		return false
	return sim.bird_touches_circle(h.x, h.y, h.radius)
