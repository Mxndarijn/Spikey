class_name ArrivalBench
extends RefCounted
## Portal arrivals into one room played by a slow player: for `delay` ticks it
## only holds its height, then PlannerBot plays `after` ticks more. Arrivals
## spread over heights, both sides and a few scores, each laid out as out of a
## real portal (GameSim._arrival_retries).
##
## The benchmark (tools/fastsim.ps1 -Mode reaction / odds run it in full):
## - EARLY_DELAY (0.75 s): no portal arrival kills. A death there must be the
##   bot's own mistake: SurvivalSearch finds a way to live from the moment the
##   player reacts.
## - SimConfig.ARRIVAL_BLIND (1 s): at most MAX_EXTRA_PCT of arrivals die
##   that would have lived with an instant reaction.

const EARLY_DELAY := 45
const MAX_EXTRA_PCT := 2


## {id, dead, causes, forced} for room `index` over `count` arrivals; `dead_now`
## and `extra` compare with the same arrivals played with no delay. `forced`
## counts deaths with no way to live (only if `check_forced`).
## `horizon` and `rollouts` set PlannerBot (lighter is faster).
static func room(
	index: int,
	count: int,
	delay: int,
	after: int,
	horizon := PlannerBot.HORIZON,
	rollouts := PlannerBot.ROLLOUTS,
	check_forced := false
) -> Dictionary:
	var slow := play(index, count, delay, after, horizon, rollouts, check_forced)
	var now := play(index, count, 0, after, horizon, rollouts)
	slow["dead_now"] = now.dead
	slow["extra"] = slow.dead - now.dead
	return slow


## Arrival `i` into room `index`, just out of the portal.
static func arrival(index: int, i: int) -> GameSim:
	var def := RoomCatalog.all()[index]
	var sim := GameSim.new(9000 + i * 37)
	sim.step(true)
	sim.state.score = maxi(def.from_score, 10) + (i % 3) * 10
	# Only heights the room can be picked at out of a portal
	# (RoomDef.arrival_skip): spread from 130 to 510 px, skipped ones moved on.
	var y := 130 + (i * 53) % 380
	while not def.fits_arrival(y * SimConfig.SUB):
		y = 130 + (y - 130 + 53) % 380
	sim.state.y = y * SimConfig.SUB
	var side := i % 2
	for k in sim._arrival_retries(side, index):
		sim._rng.next_u32()
	sim._arrive_in(side, index)
	return sim


## Holds the bird's height for `delay` ticks (a player still reading the room).
## False if it died meanwhile.
static func hold(sim: GameSim, delay: int) -> bool:
	var y0 := sim.state.y
	var g := sim.room.gravity
	for n in delay:
		sim.step((sim.state.y - y0) * g > 0 and sim.state.vy * g >= 0)
		if sim.is_over():
			return false
	return true


## Whether arrival `i` leaves no way to live for `after` ticks once the player
## reacts after `delay`.
static func forced(index: int, i: int, delay: int, after: int) -> bool:
	var sim := arrival(index, i)
	if not hold(sim, delay):
		return true
	return not SurvivalSearch.new().run(sim, after)


static func play(
	index: int,
	count: int,
	delay: int,
	after: int,
	horizon := PlannerBot.HORIZON,
	rollouts := PlannerBot.ROLLOUTS,
	check_forced := false
) -> Dictionary:
	var def := RoomCatalog.all()[index]
	var dead := 0
	var forced_count := 0
	var causes := {}
	for i in count:
		var sim := arrival(index, i)
		var y0 := sim.state.y
		var bot := PlannerBot.new(i + 1, horizon, rollouts)
		var n := 0
		while n < delay + after and not sim.is_over():
			var tap: bool
			if n < delay:
				var g := sim.room.gravity
				tap = (sim.state.y - y0) * g > 0 and sim.state.vy * g >= 0
			else:
				tap = bot.decide(sim)
			sim.step(tap)
			n += 1
		if sim.is_over():
			dead += 1
			var why: String = SimState.DeathCause.keys()[sim.state.death_cause]
			var key := "%s@%s" % [why, "blind" if n <= delay else "play"]
			causes[key] = int(causes.get(key, 0)) + 1
			if check_forced and forced(index, i, delay, after):
				forced_count += 1
	return {"id": def.id, "dead": dead, "causes": causes, "forced": forced_count}
