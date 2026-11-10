class_name ArrivalBench
extends RefCounted
## Portal arrivals into one room played by a slow player: for `delay` ticks it
## only holds its height, then PlannerBot plays `after` ticks more. Arrivals
## spread over heights, both sides and a few scores, each laid out as out of a
## real portal (GameSim._arrival_retries).

## The benchmark: a slow reaction (SimConfig.ARRIVAL_BLIND ticks) may cost a
## room at most this share of its arrivals over an instant one (percent).
const MAX_EXTRA_PCT := 5


## {id, dead, causes} for room `index` over `count` arrivals; `dead_now` and
## `extra` compare with the same arrivals played with no delay.
## `horizon` and `rollouts` set PlannerBot (lighter is faster).
static func room(
	index: int,
	count: int,
	delay: int,
	after: int,
	horizon := PlannerBot.HORIZON,
	rollouts := PlannerBot.ROLLOUTS
) -> Dictionary:
	var slow := _play(index, count, delay, after, horizon, rollouts)
	var now := _play(index, count, 0, after, horizon, rollouts)
	slow["dead_now"] = now.dead
	slow["extra"] = slow.dead - now.dead
	return slow


static func _play(
	index: int, count: int, delay: int, after: int, horizon: int, rollouts: int
) -> Dictionary:
	var def := RoomCatalog.all()[index]
	var dead := 0
	var causes := {}
	for i in count:
		var sim := GameSim.new(9000 + i * 37)
		sim.step(true)
		sim.state.score = maxi(def.from_score, 10) + (i % 3) * 10
		sim.state.y = (130 + (i * 53) % 380) * SimConfig.SUB
		var side := i % 2
		for k in sim._arrival_retries(side, index):
			sim._rng.next_u32()
		sim._arrive_in(side, index)
		var y0 := sim.state.y
		var bot := PlannerBot.new(i + 1, horizon, rollouts)
		var n := 0
		while n < delay + after and not sim.is_over():
			var tap: bool
			if n < delay:
				var g := sim.room.def.gravity_sign
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
	return {"id": def.id, "dead": dead, "causes": causes}
