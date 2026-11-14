extends TestCase
## A Calm/Wild fork's two exits are always where the bird can fly through
## them: on both walls of every room that hosts a fork, nothing deadly is in
## either mouth (ExitPlanner.in_mouth: not in a cave's rock). A room with one
## short way out per wall (Cave Tunnel) has no room for two exits FORK_APART
## apart, so it is never picked when its exit would be a fork
## (RoomDef.hosts_fork, RoomCatalog.pick_next). The full sweep (40 arrivals per
## variant at three fork scores) runs on FastSim-RS: `fastsim-rs check
## forkexits` (tools/fastsim-rs/fastsim/src/checks/forkexits.rs), part of
## tools/check.ps1. Here: two arrivals per variant at the first fork.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

## The score before the first fork exit (SimConfig.FORK_EVERY).
const FORK_SCORE := SimConfig.FORK_EVERY - SimConfig.POINTS_PER_ROOM


func test_both_fork_exits_are_free_in_every_room() -> void:
	var rooms := RoomCatalog.all()
	var forks := 0
	for c: Array in ArrivalBench.cases():
		var def := rooms[c[0]]
		if def.boss or not def.hosts_fork:
			continue
		for i in 2:
			var sim := ArrivalBench.arrival(c[0], i, c[1], FORK_SCORE)
			assert_true(ExitPlanner.is_fork(sim, sim.state.plan_at), "%s/%s fork" % [def.id, c[1]])
			forks += 1
			var s := sim.state
			for wall: Array in [
				[0, s.plan_a_y_left, s.plan_b_y_left], [1, s.plan_a_y_right, s.plan_b_y_right]
			]:
				for y: int in [wall[1], wall[2]]:
					assert_false(
						ExitPlanner.in_mouth(sim, wall[0], y),
						(
							"%s/%s arrival %d: fork exit at %d px on wall %d is in a hazard"
							% [def.id, sim.room.variant_id(), i, y / SimConfig.SUB, wall[0]]
						)
					)
	assert_true(forks > 100, "%d fork plans" % forks)


func test_a_room_that_hosts_no_fork_never_gets_a_fork_exit() -> void:
	var rooms := RoomCatalog.all()
	var later := 0
	for score: int in [FORK_SCORE, FORK_SCORE + SimConfig.POINTS_PER_ROOM]:
		var fork := ExitPlanner.fork_at(score + SimConfig.POINTS_PER_ROOM)
		for season in range(Seasons.NONE, Seasons.COUNT):
			var rng := SimRng.new(score * 1000 + season + 7)
			for k in 60:
				var st := SimState.new()
				st.score = score
				st.anchor_y = (130 + (k * 53) % 380) * SimConfig.SUB
				st.deck_lo = rng.next_u32() & rng.next_u32()
				var got := RoomCatalog.pick_next(rng, st, -1, season)
				if got < 0 or rooms[got].hosts_fork:
					continue
				assert_false(
					fork, "score %d season %d: %s for a fork exit" % [score, season, rooms[got].id]
				)
				later += 1
	assert_true(later > 0, "a room that hosts no fork still comes up off fork exits")


## Why Cave Tunnel hosts no fork: at a fork score its exits would sit in the
## rock (the planner finds no two free slots FORK_APART apart on a wall).
func test_a_cave_has_no_room_for_a_fork() -> void:
	var index := RoomCatalog.index_of("cave")
	assert_false(RoomCatalog.all()[index].hosts_fork)
	var in_rock := 0
	for i in 4:
		var sim := ArrivalBench.arrival(index, i, "drips", FORK_SCORE)
		var s := sim.state
		for wall: Array in [
			[0, s.plan_a_y_left, s.plan_b_y_left], [1, s.plan_a_y_right, s.plan_b_y_right]
		]:
			for y: int in [wall[1], wall[2]]:
				if ExitPlanner.in_mouth(sim, wall[0], y):
					in_rock += 1
	assert_true(in_rock > 0, "a fork's exits do not fit in a cave")
