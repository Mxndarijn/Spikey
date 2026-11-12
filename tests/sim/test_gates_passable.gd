extends TestCase
## Shutter Gates: the portal can always be reached. An exit is only planned
## where the bird can get to from the gap of the last gate (Gate.blocks_exit).
## The SurvivalSearch cases (through the portal from many
## seeds, and after a revive) run on FastSim-RS: `tools/fastsim.ps1 -Mode check
## -Check gates` (tools/fastsim-rs/fastsim/src/checks/searches.rs), part of
## tools/check.ps1. Here: the exit planning rule.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const Gate := preload("res://sim/hazards/gate.gd")


static func practice(seed_value: int, variant: String = "classic") -> GameSim:
	var index := RoomCatalog.index_of("gates")
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)


## A planned exit is never further from the last gate's gap than Gate.EXIT_REACH.
func test_exits_are_planned_near_the_gap() -> void:
	for seed_value in range(1, 60):
		var sim := practice(seed_value, "classic" if seed_value % 2 == 0 else "single")
		# Some time into the room, the bird has just bounced off wall `side`:
		# the ghost goes there, and the bird is back in two crossings.
		for i in 1 + seed_value * 7 % 400:
			sim.room.step(sim)
		var side := seed_value % 2
		var r := SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X if side == 0 else -SimConfig.SPEED_X
		sim.state.x = r if side == 0 else SimConfig.WORLD_W - r
		# One point before the exit, as a ghost (or a revive) plans it.
		sim.state.score = sim.next_exit_score() - 1
		ExitPlanner.plan(sim, sim._rng, side, sim.state.score + 1)
		# The gate next to that wall, when the bird passes it on its way back.
		var last: Hazard = sim.room.hazards[mini(side, sim.room.hazards.size() - 1)]
		var steps := sim.steps_to_wall(side) - absi(last.x - sim.state.x) / SimConfig.SPEED_X
		var gap: int = last.gap_at(last.t + steps)
		assert_true(
			absi(sim.state.exit_a_y - gap) <= Gate.EXIT_REACH,
			"seed %d: exit %d px from the gap" % [seed_value, absi(sim.state.exit_a_y - gap) / 64]
		)
