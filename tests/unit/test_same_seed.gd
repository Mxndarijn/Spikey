extends TestCase
## Two players of one seed who take the same portals get the same run: the
## same rooms, variants, hazards, wall spikes and exits, however they fly
## (taps, heights, coins taken). Generation never reads the bird's own
## height (SimState.anchor_y) and each room and wall has its own RNG.

## A real v21 run whose rooms changed with the player's height out of a portal.
const SEEDS: Array[int] = [3392377610, 11, 2024, 31337]
const TICKS := 3000
## Hazards that copy the bird itself (Echo flies the bird's path back).
const FOLLOWS_BIRD: Array[String] = ["echo"]


## What generation made in one run, keyed so two runs can be compared:
## "room N" -> the room, "wall N:W" -> wall W's spikes, "exit N:S" -> the exit
## planned at score S. Also the bird's height out of each portal.
func _record(seed_value: int, bot_seed: int, wait: int) -> Dictionary:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(bot_seed)
	var out := {}
	var heights: Array[int] = []
	var taps := 0
	while not sim.is_over() and sim.state.tick < TICKS:
		var tap := sim.state.tick >= wait and SimBots.gap_seeker(sim, rng)
		if tap:
			taps += sim.state.tick
		sim.step(tap)
		var s := sim.state
		var n := s.room_index
		if sim.events.has(GameSim.Event.ROOM_CHANGE):
			out["room %d" % n] = [s.room_kind, sim.room.variant, sim.room.rng_seed, _hazards(sim)]
			heights.append(s.y)
		if sim.events.has(GameSim.Event.ROOM_CHANGE) or sim.events.has(GameSim.Event.BOUNCE):
			var mask := s.right_spikes if s.vx > 0 else s.left_spikes
			out["wall %d:%d" % [n, sim.room.walls]] = mask
		if sim.events.has(GameSim.Event.EXIT_PREVIEW) or sim.events.has(GameSim.Event.EXIT_OPEN):
			out["exit %d:%d" % [n, s.score]] = [s.exit_side, s.exit_a_y, s.exit_b_y]
	return {"made": out, "heights": heights, "taps": taps}


func _hazards(sim: GameSim) -> Array[int]:
	var out: Array[int] = []
	for h in sim.room.hazards:
		if not FOLLOWS_BIRD.has(h.kind):
			out.append(h.checksum(SimHash.SEED))
	return out


func test_two_players_of_one_seed_get_the_same_rooms_spikes_and_exits() -> void:
	var rooms_compared := 0
	var heights_differed := false
	for seed_value in SEEDS:
		var a := _record(seed_value, 1, 0)
		var b := _record(seed_value, 7, 23)
		assert_true(a.taps != b.taps, "seed %d: the two players tap differently" % seed_value)
		var made_a: Dictionary = a.made
		var made_b: Dictionary = b.made
		for key: String in made_a:
			if not made_b.has(key):
				continue
			assert_eq(made_b[key], made_a[key], "seed %d: %s" % [seed_value, key])
			if key.begins_with("room ") and key != "room 0":
				rooms_compared += 1
		var ha: Array[int] = a.heights
		var hb: Array[int] = b.heights
		for i in mini(ha.size(), hb.size()):
			if ha[i] != hb[i]:
				heights_differed = true
	assert_true(rooms_compared >= 3, "both players got through portals (%d rooms)" % rooms_compared)
	assert_true(heights_differed, "at least one portal at different heights")


## A revive restarts the room as the bird came in, so the walls after it are
## the room's own again: the same as a player who never died there.
func test_walls_after_a_revive_are_the_rooms_own() -> void:
	var sim := GameSim.new(2024)
	var rng := SimRng.new(1)
	var walls := {}
	while not sim.is_over() and sim.state.tick < TICKS and sim.state.room_index < 1:
		sim.step(SimBots.gap_seeker(sim, rng))
	assert_eq(sim.state.room_index, 1, "the bot reached room 1")
	var copy := SimCopy.copy(sim)
	# One player plays on; the other dives into the floor and revives.
	for i in 400:
		if sim.is_over():
			break
		sim.step(SimBots.gap_seeker(sim, rng))
		if sim.events.has(GameSim.Event.BOUNCE) and sim.state.room_index == 1:
			walls[sim.room.walls] = sim.state.right_spikes if sim.state.vx > 0 else sim.state.left_spikes
	while not copy.is_over():
		copy.step(false)
	assert_true(copy.revive(), "revived")
	var rng2 := SimRng.new(1)
	var checked := 0
	for i in 600:
		if copy.is_over() or copy.state.room_index != 1:
			break
		copy.step(SimBots.gap_seeker(copy, rng2))
		if copy.events.has(GameSim.Event.BOUNCE) and walls.has(copy.room.walls):
			var mask := copy.state.right_spikes if copy.state.vx > 0 else copy.state.left_spikes
			assert_eq(mask, walls[copy.room.walls], "wall %d" % copy.room.walls)
			checked += 1
	assert_true(checked >= 2, "compared %d walls after the revive" % checked)
