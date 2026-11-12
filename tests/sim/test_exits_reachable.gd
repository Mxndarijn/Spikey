extends TestCase
## Seed 3392377610 (v21): its room 3 was Stalactite Run's floor variant. The
## fangs went to the bird's height at every bounce and the exit could open
## anywhere, so a bird that was high when a low exit showed had no way in.
## Now a room's exits are picked when it starts (ExitPlanner.plan_room), the
## same for every player, and near an exit the anchor, the fangs and the
## walls steer to it. The search side of this test is the FastSim check
## `reach` (tools/fastsim/Checks.cs); this one checks the rules it relies on.

const Stalactite := preload("res://sim/hazards/stalactite.gd")
const SEEDS := 3


static func _stalac_floor(seed_value: int) -> GameSim:
	var index := RoomCatalog.index_of("stalac")
	return GameSim.new(1000 + seed_value * 61, Seasons.NONE, index, "floor")


## Plays a surviving line until the ghost shows: the search's, after `wait`
## ticks without a tap (a slower start: another player). Returns the sim then.
static func _to_ghost(sim: GameSim, wait: int) -> GameSim:
	for i in wait:
		sim.step(false)
	var search := SurvivalSearch.new()
	search.run(SimCopy.copy(sim), 1100)
	for tap in search.best_inputs:
		if sim.is_over() or sim.state.exit_preview:
			break
		sim.step(tap == 1)
	return sim


func test_every_exit_can_be_reached_when_it_opens() -> void:
	var shown := 0
	for s in SEEDS:
		var planned_left := _stalac_floor(s).state.plan_a_y_left
		var planned_right := _stalac_floor(s).state.plan_a_y_right
		# Two players, flying differently, meet the exit the room planned.
		for wait in [0, 23]:
			var sim := _to_ghost(_stalac_floor(s), wait)
			if sim.is_over():
				continue
			shown += 1
			var st := sim.state
			var planned := planned_left if st.exit_side == 0 else planned_right
			assert_eq(st.exit_a_y, planned, "seed %d: the exit the room planned" % s)
			# The ghost's bounce moved the anchor toward the exit, and the
			# fangs were set around the anchor, never the bird.
			var near_exit := absi(st.anchor_y - st.exit_a_y)
			for h in sim.room.hazards:
				var f := h as Stalactite
				if f == null:
					continue
				var off := absi(f.target_y - st.anchor_y)
				assert_true(
					off <= Stalactite.REACH + Stalactite.MAX_STEP,
					"seed %d: a fang is set %d px off the anchor" % [s, off / SimConfig.SUB]
				)
			assert_true(
				near_exit <= absi(st.y - st.exit_a_y) or near_exit <= RoomRules.GAP_REACH,
				"seed %d: the anchor is near the exit" % s
			)
	assert_true(shown >= SEEDS, "the bots reached the ghost (%d)" % shown)


## The exit at room start never depends on how the bird flies: the plan is
## drawn from the room's own RNG before the bird moves.
func test_the_room_plans_its_exits_when_it_starts() -> void:
	var sim := _stalac_floor(3)
	var st := sim.state
	assert_eq(st.plan_at, sim.next_exit_score(), "planned for the next exit")
	for y: int in [st.plan_a_y_left, st.plan_a_y_right]:
		assert_between(y, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		assert_true(ExitPlanner.reserved(sim, 0, st.plan_a_y_left), "its zone is reserved")
	var again := _stalac_floor(3)
	again.state.y = 500 * SimConfig.SUB
	ExitPlanner.plan_room(again, again.next_exit_score())
	assert_eq(again.state.plan_a_y_left, st.plan_a_y_left, "the bird's height changes nothing")
	assert_eq(again.state.plan_a_y_right, st.plan_a_y_right)
