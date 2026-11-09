extends TestCase
## Shutter Gates: the portal can always be reached. An exit is only planned
## where the bird can get to from the gap of the last gate (Gate.blocks_exit),
## and after a revive the gaps lead from the bird to the exit that stayed
## (Gate.aim_at_exit). SurvivalSearch must find a way through the portal.

const Gate := preload("res://sim/hazards/gate.gd")

## Practice seeds whose first portal no way of tapping could reach before
## exits looked at the gates (the gap was 200 px or more from the exit when
## the bird came through the last gate): [seed, ticks to be through it].
const ONCE_IMPOSSIBLE := [[141, 960], [144, 960]]
## Seeds for the quick runs, which start a point or two before the exit.
const SEEDS := 14
## Ticks for a quick run: up to three crossings and some of the portal wait.
const QUICK_TICKS := 290


static func practice(seed_value: int) -> GameSim:
	var index := RoomCatalog.index_of("gates")
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index)


func test_once_unreachable_portals_are_reachable() -> void:
	for c: Array in ONCE_IMPOSSIBLE:
		_assert_through(practice(c[0]), c[1], "seed %d" % c[0])


## Many seeds, each started just before its exit is planned: as a ghost one
## point early (two crossings later the bird flies into it), and with no ghost
## (it opens on the wall ahead at once).
func test_the_portal_is_reachable() -> void:
	var every := SimConfig.POINTS_PER_ROOM
	for i in SEEDS:
		var seed_value := 500 + i * 37
		var sim := practice(seed_value)
		var ghost := i % 4 != 3
		sim.state.score += every - (2 if ghost else 1)
		_assert_through(
			sim, QUICK_TICKS, "seed %d (%s)" % [seed_value, "ghost" if ghost else "open"]
		)


## A planned exit is never further from the last gate's gap than Gate.EXIT_REACH.
func test_exits_are_planned_near_the_gap() -> void:
	for seed_value in range(1, 60):
		var sim := practice(seed_value)
		# Some time into the room, the bird has just bounced off wall `side`:
		# the ghost goes there, and the bird is back in two crossings.
		for i in 1 + seed_value * 7 % 400:
			sim.room.step(sim)
		var side := seed_value % 2
		var r := SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X if side == 0 else -SimConfig.SPEED_X
		sim.state.x = r if side == 0 else SimConfig.WORLD_W - r
		sim._plan_exit(side, sim.state.score + SimConfig.POINTS_PER_ROOM)
		# The gate next to that wall, when the bird passes it on its way back.
		var last: Hazard = sim.room.hazards[side]
		var steps := sim.steps_to_wall(side) - absi(last.x - sim.state.x) / SimConfig.SPEED_X
		var gap: int = last.gap_at(last.t + steps)
		assert_true(
			absi(sim.state.exit_a_y - gap) <= Gate.EXIT_REACH,
			"seed %d: exit %d px from the gap" % [seed_value, absi(sim.state.exit_a_y - gap) / 64]
		)


## A revive keeps the exit where it was and restarts the gates: whichever
## height the exit has, on either wall, open or still a ghost, the bird can
## get through it.
func test_the_portal_is_reachable_after_a_revive() -> void:
	var crossing := SimConfig.WORLD_W / SimConfig.SPEED_X
	var n := 0
	for slot in range(1, SimConfig.SLOT_COUNT - 1, 2):
		for side in 2:
			# Alternate, so every height gets both cases across the two walls.
			var open := n % 2 == 0
			n += 1
			var sim := revived(100 + n, open, side, SimConfig.slot_center_y(slot))
			var ticks := SimConfig.ARRIVAL_HOLD + crossing * (1 if open else 2) + 20
			var what := "%s exit at slot %d on wall %d" % ["open" if open else "ghost", slot, side]
			_assert_through(sim, ticks, what)


## A real run in the gates room with an exit at `exit_y` on wall `side`, open or
## planned (a ghost), killed and revived.
static func revived(seed_value: int, open: bool, side: int, exit_y: int) -> GameSim:
	var index := RoomCatalog.index_of("gates")
	var def: RoomDef = RoomCatalog.all()[index]
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	sim.state.score = base if open else base + every - 1
	sim._enter_room(index)
	sim._plan_exit(side, base if open else base + every)
	sim.state.exit_a_y = exit_y
	sim.state.exit_open = open
	sim.state.exit_preview = not open
	sim.kill(SimState.DeathCause.HAZARD)
	sim.revive()
	return sim


func _assert_through(sim: GameSim, ticks: int, what: String) -> void:
	var start_room := sim.state.room_index
	var search := SurvivalSearch.new()
	var ok := search.run(sim, ticks)
	assert_true(
		ok, "%s: all died at tick %d (%s)" % [what, search.ticks_survived, search.last_deaths]
	)
	if ok:
		assert_true(
			search.best.state.room_index > start_room, "%s: nobody got through the portal" % what
		)
