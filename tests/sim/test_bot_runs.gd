extends TestCase
## Many simulated runs on random seeds: catches crashes, broken invariants and
## rooms that are too hard for a simple bot to get through.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const RANDOM_RUNS := 150
const SEEKER_RUNS := 40


func test_random_tapper_keeps_invariants() -> void:
	var seeds := SimRng.new(1001)
	for run in RANDOM_RUNS:
		var sim := GameSim.new(seeds.next_u32())
		var bot := SimRng.new(run + 1)
		var last_score := 0
		while not sim.is_over() and sim.state.tick < 20000:
			sim.step(SimBots.random_tapper(sim, bot))
			var s := sim.state
			if not _check_invariants(s, last_score, run):
				return
			last_score = s.score
		assert_true(sim.is_over(), "run %d ended" % run)


func test_gap_seeker_clears_several_rooms() -> void:
	var seeds := SimRng.new(2002)
	var best := 0
	var total := 0
	var room_changes := 0
	for run in SEEKER_RUNS:
		var replay := SimBots.play(seeds.next_u32(), SimBots.gap_seeker, run + 1)
		best = maxi(best, replay.score)
		total += replay.score
		if replay.score >= SimConfig.POINTS_PER_ROOM:
			room_changes += 1
	print("    gap_seeker: best %d, average %d" % [best, total / SEEKER_RUNS])
	assert_true(
		best >= 3 * SimConfig.POINTS_PER_ROOM, "best bot run reaches room 4 (got %d)" % best
	)
	assert_true(room_changes >= SEEKER_RUNS / 2, "most bot runs change room at least once")


func _check_invariants(s: SimState, last_score: int, run: int) -> bool:
	var r := SimConfig.BIRD_RADIUS
	var ok := true
	if s.x - r < -SimConfig.SPEED_X or s.x + r > SimConfig.WORLD_W + SimConfig.SPEED_X:
		fail("run %d tick %d: bird outside side walls (x=%d)" % [run, s.tick, s.x])
		ok = false
	if s.score < last_score or s.score > last_score + 1:
		fail("run %d tick %d: score jumped %d -> %d" % [run, s.tick, last_score, s.score])
		ok = false
	# Rooms change through exits, which open every POINTS_PER_ROOM points.
	if s.room_index > s.score / SimConfig.POINTS_PER_ROOM:
		fail("run %d tick %d: room %d at score %d" % [run, s.tick, s.room_index, s.score])
		ok = false
	if s.left_spikes != 0 and s.right_spikes != 0:
		fail("run %d tick %d: both walls have spikes" % [run, s.tick])
		ok = false
	return ok
