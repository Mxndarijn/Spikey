extends TestCase
## A revive must never be a second death sentence: in every room, whatever the
## exit was doing when the bird died, SurvivalSearch finds a way to live on
## after the revive (through the portal wait and the first seconds of flight).

## Ticks after the revive each case must be survivable for.
const TICKS := SimConfig.ARRIVAL_HOLD + 180
const CASES: Array[String] = ["none", "open", "ghost"]


func test_every_room_is_survivable_after_a_revive() -> void:
	var rooms := RoomCatalog.all()
	for index in rooms.size():
		# The search is slow, so each room gets one exit case and one wall here;
		# across the rooms every case and both walls come up. (All rooms x all
		# cases passed when revive was added: loop over CASES to run that again.)
		var exit := CASES[index % CASES.size()]
		var side := (index / CASES.size()) % 2
		var sim := revived(index, 9000 + index, exit, side)
		var search := SurvivalSearch.new()
		var ok := search.run(sim, TICKS)
		assert_true(
			ok,
			(
				"%s, exit %s on wall %d: all died %d ticks after the revive (%s)"
				% [rooms[index].id, exit, side, search.ticks_survived, search.last_deaths]
			)
		)


## A real run put in room `index` at a score that fits `exit` ("none", "open"
## or "ghost" on wall `side`), killed there and revived.
static func revived(index: int, seed_value: int, exit: String, side: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	sim.state.score = base + 3
	sim._enter_room(index)
	sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	match exit:
		"open":
			sim.state.score = base
			sim._plan_exit(side, base)
			sim.state.exit_open = true
		"ghost":
			sim.state.score = base + every - 1
			sim._plan_exit(side, base + every)
			sim.state.exit_preview = true
	sim.kill(SimState.DeathCause.FLOOR)
	sim.revive()
	return sim
