class_name VariantCheck
extends RefCounted
## The fairness check every GENERATED variant's layout passes (RoomRuntime
## retries with the next draws until one does, then builds the recipe's safe
## fallback). Out of a portal a bird anywhere in the exit it came through
## (GameSim.ARRIVAL_HEIGHTS around the PLANNED height, SimState.anchor_y) that
## only holds its height for HOLD_STEPS moving steps (the reading time: the
## room is frozen during the portal hold) touches nothing deadly. The way on
## from there is ArrivalCheck's (GameSim._arrival_retries), the exits are
## ExitPlanner's (blocks_exit) and the warnings are the hazards' own, as for
## every room. Plays copies only: no RNG draws, the room is left as it is.

## Moving steps the bird only holds its height (SimConfig.ARRIVAL_BLIND: a
## second of flight, more than the reading time left after PORTAL_HOLD).
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
		if not _holds_at(sim, GameSim._arrival_y(sim.state.anchor_y + dy), avoid_touch, n):
			return false
	return true


## One bird holding height `hold`, as FairLanes.arrival_path flies it.
static func _holds_at(sim: GameSim, hold: int, avoid_touch: bool, steps: int) -> bool:
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
			if not h.alive:
				continue
			if h.kills(c) or (avoid_touch and _touches(c, h)):
				return false
	return true


## Whether the bird touches a bubble's body.
static func _touches(sim: GameSim, h: Hazard) -> bool:
	if h.kind != "bubble":
		return false
	return sim.bird_touches_circle(h.x, h.y, h.radius)
