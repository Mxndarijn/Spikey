extends TestCase
## Variants that change the walls, gravity or light: Crowded (Lopsided, Spike
## storm), Squeeze Box (Left press, Breathing box), Blink Walls (Fast blink),
## Hunter Spike (Twin hunters), Gravity Flip (Flip-flop) and Midnight Cage
## (Lantern, Flicker).

const SUB := SimConfig.SUB
const Dart := preload("res://sim/hazards/dart.gd")
const MID_Y := (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2


## A sim in room `id` playing variant `variant`, the bird not started yet.
static func sim_in(id: String, variant: String, seed_value: int = 3) -> GameSim:
	var index := RoomCatalog.index_of(id)
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)


func test_variant_lists() -> void:
	var want := {
		"crowded": ["classic", "lopsided", "storm"],
		"squeeze": ["classic", "left-only", "breathing"],
		"blink": ["classic", "fast"],
		"hunter": ["classic", "twin"],
		"flip": ["classic", "flip-flop"],
		"midnight": ["classic", "lantern", "flicker"],
	}
	for id: String in want:
		var ids: Array[String] = []
		for v in RoomCatalog.find(id).variants:
			ids.append(v.id)
		assert_eq(ids, want[id], "%s variants" % id)
		assert_eq(sim_in(id, want[id][1]).room.variant_id(), want[id][1], "%s forced" % id)


# --- Crowded ----------------------------------------------------------------


func test_lopsided_packs_the_left_wall() -> void:
	var sim := sim_in("crowded", "lopsided")
	var def := sim.room.def
	var left := RoomRules.spike_count(30, def, sim.room.spike_bonus(0))
	var right := RoomRules.spike_count(30, def, sim.room.spike_bonus(1))
	var normal := RoomRules.spike_count(30, def)
	assert_true(left > normal, "more on the left")
	assert_true(right < normal, "fewer on the right")
	assert_true(right >= 1, "the right wall keeps a spike")
	assert_true(left <= SimConfig.SLOT_COUNT - def.gap, "the left wall keeps its gap")


func test_lopsided_walls_get_their_own_counts() -> void:
	var sim := sim_in("crowded", "lopsided", 11)
	sim.state.score = 30
	var seen_left := {}
	var seen_right := {}
	for i in 20:
		sim._new_wall(0)
		sim._new_wall(1)
		seen_left[_bits(sim.state.left_spikes)] = true
		seen_right[_bits(sim.state.right_spikes)] = true
	assert_eq(seen_left.keys(), [RoomRules.spike_count(30, sim.room.def, 2)])
	assert_eq(seen_right.keys(), [RoomRules.spike_count(30, sim.room.def, -2)])


func test_spike_storm_adds_two_per_wall() -> void:
	var sim := sim_in("crowded", "storm")
	var def := sim.room.def
	for side in 2:
		assert_eq(sim.room.spike_bonus(side), 2)
	assert_eq(RoomRules.spike_count(10, def, 2), RoomRules.spike_count(10, def) + 2)
	assert_eq(sim.room.spike_depth(), SimConfig.SPIKE_DEPTH, "normal size spikes")


# --- Squeeze Box --------------------------------------------------------------


func test_left_press_moves_only_the_left_wall() -> void:
	var sim := sim_in("squeeze", "left-only")
	sim.room.points = 4
	assert_eq(sim.room.wall_left(), 4 * RoomRuntime.SQUEEZE_LEFT_STEP)
	assert_eq(sim.room.wall_right(), SimConfig.WORLD_W, "the right wall stays")
	sim.room.points = 50
	assert_eq(sim.room.wall_left(), RoomRuntime.SQUEEZE_MAX_POINTS * RoomRuntime.SQUEEZE_LEFT_STEP)
	var classic := sim_in("squeeze", "classic")
	classic.room.points = 4
	assert_eq(classic.room.wall_right(), SimConfig.WORLD_W - 4 * RoomRuntime.SQUEEZE_STEP)


func test_left_press_leaves_room_to_fly() -> void:
	var most := RoomRuntime.SQUEEZE_MAX_POINTS * RoomRuntime.SQUEEZE_LEFT_STEP
	var classic := RoomRuntime.SQUEEZE_MAX_POINTS * RoomRuntime.SQUEEZE_STEP * 2
	assert_true(most <= classic * 3 / 4, "squeezes less in all than both walls do")


func test_breathing_box_pushes_in_and_eases_back() -> void:
	var sim := sim_in("squeeze", "breathing")
	assert_eq(sim.room.inset(0), 0, "starts at full width")
	var most := 0
	var fastest := 0
	var last := 0
	for t in RoomRuntime.BREATHE_PERIOD + 1:
		sim.room.t = t
		var now := sim.room.inset(0)
		assert_eq(sim.room.inset(1), now, "both walls together")
		most = maxi(most, now)
		fastest = maxi(fastest, absi(now - last))
		last = now
	assert_eq(most, RoomRuntime.BREATHE_IN, "in all the way")
	assert_eq(last, 0, "and back out")
	assert_true(fastest * 4 < SimConfig.SPEED_X, "a wall is far slower than the bird")
	sim.room.t = 0
	sim.room.points = 6
	assert_eq(sim.room.inset(0), 0, "points don't squeeze it")


# --- Blink Walls --------------------------------------------------------------


func test_fast_blink_swaps_twice_a_second() -> void:
	var sim := sim_in("blink", "fast")
	sim.room.blink_left = 0b101
	sim.room.t = 0
	assert_eq(sim.room.wall_mask(0, 0b11), 0b11)
	sim.room.t = 30
	assert_eq(sim.room.wall_mask(0, 0b11), 0b101, "the second pattern after half a second")
	sim.room.t = 60
	assert_eq(sim.room.wall_mask(0, 0b11), 0b11)
	var classic := sim_in("blink", "classic")
	classic.room.blink_left = 0b101
	classic.room.t = 30
	assert_eq(classic.room.wall_mask(0, 0b11), 0b11, "the classic blink waits a second")


func test_fast_blink_patterns_share_a_free_run() -> void:
	var sim := sim_in("blink", "fast", 21)
	for score in [80, 120, 200]:
		sim.state.score = score
		for i in 30:
			sim._new_wall(i % 2)
			var first := sim.state.left_spikes if i % 2 == 0 else sim.state.right_spikes
			var second := sim.room.blink_left if i % 2 == 0 else sim.room.blink_right
			assert_true(
				RoomRules.longest_gap(first | second) >= sim.room.def.gap,
				"score %d: a lane free in both patterns" % score
			)


func test_longest_gap_mask() -> void:
	assert_eq(RoomRules.longest_gap_mask(0b1111111110000), 0b1111)
	assert_eq(RoomRules.longest_gap_mask(0b1100001000011), 0b111100, "the first of two")
	assert_eq(RoomRules.longest_gap_mask((1 << SimConfig.SLOT_COUNT) - 1), 0)
	assert_eq(RoomRules.longest_gap_mask(0), (1 << SimConfig.SLOT_COUNT) - 1)


# --- Hunter Spike -------------------------------------------------------------


func test_twin_hunters_fire_from_their_own_walls_in_turn() -> void:
	var sim := sim_in("hunter", "twin")
	var darts: Array[Dart] = []
	for h in sim.room.hazards:
		if h is Dart:
			darts.append(h as Dart)
	assert_eq(darts.size(), 2, "two hunters")
	var sides := {}
	for d in darts:
		sides[d.home] = true
		assert_eq(d.side, d.home, "starts on its wall")
	assert_eq(sides.size(), 2, "one on each wall")
	assert_eq(darts[1].wait - darts[0].wait, Dart.TWIN_DELAY, "a beat apart")
	# Fly a while (the bird can't die): each fires from its own wall only.
	sim.step(true)
	var fired: Array[Dictionary] = [{}, {}]
	for i in 900:
		_hold(sim)
		sim.step(false)
		for k in 2:
			if darts[k].state == Dart.State.FLY:
				fired[k][darts[k].side] = true
	for k in 2:
		assert_eq(fired[k].keys(), [darts[k].home], "hunter %d keeps its wall" % k)


func test_classic_hunter_still_picks_the_far_wall() -> void:
	var sim := sim_in("hunter", "classic")
	assert_eq(sim.room.hazards.size(), 1)
	assert_eq((sim.room.hazards[0] as Dart).home, -1)


# --- Gravity Flip -------------------------------------------------------------


func test_flip_flop_turns_gravity_round_at_every_bounce() -> void:
	var sim := sim_in("flip", "flip-flop")
	assert_eq(sim.room.gravity, -1, "starts pulling up, like the room")
	sim.step(true)
	assert_true(sim.state.vy > 0, "a flap pushes down")
	var bounces := 0
	var last_vx := sim.state.vx
	var seen := {}
	for i in 600:
		_hold(sim)
		sim.step(false)
		if sim.state.vx != last_vx:
			last_vx = sim.state.vx
			bounces += 1
			seen[sim.room.gravity] = true
			assert_eq(sim.room.gravity, -1 if bounces % 2 == 0 else 1, "bounce %d" % bounces)
	assert_true(bounces >= 3, "bounced a few times")
	assert_eq(seen.size(), 2, "pulled both ways")


func test_flap_pushes_against_gravity_after_a_flip() -> void:
	var sim := sim_in("flip", "flip-flop")
	sim.step(true)
	sim.room.gravity = 1
	sim.step(true)
	assert_true(sim.state.vy < 0, "pulled down: a flap pushes up")


func test_classic_flip_never_turns() -> void:
	var sim := sim_in("flip", "classic")
	sim.step(true)
	for i in 400:
		_hold(sim)
		sim.step(false)
		assert_eq(sim.room.gravity, -1)


# --- Midnight Cage ------------------------------------------------------------


func test_midnight_variants_play_the_same() -> void:
	var sums: Array[int] = []
	for v: String in ["classic", "lantern", "flicker"]:
		var sim := sim_in("midnight", v, 7)
		assert_eq(sim.room.spike_bonus(0), 0, v)
		assert_eq(sim.room.spike_depth(), SimConfig.SPIKE_DEPTH, v)
		sim.step(true)
		for i in 300:
			sim.step(i % 15 == 0)
		sums.append(sim.state.y * 7 + sim.state.score + int(sim.state.alive))
	assert_eq(sums[1], sums[0], "lantern plays like classic")
	assert_eq(sums[2], sums[0], "flicker plays like classic")


## Keeps the bird alive and level in the middle of the room, walls bare.
func _hold(sim: GameSim) -> void:
	sim.state.alive = true
	sim.state.y = MID_Y
	sim.state.vy = 0
	sim.state.left_spikes = 0
	sim.state.right_spikes = 0


func _bits(mask: int) -> int:
	var n := 0
	for slot in SimConfig.SLOT_COUNT:
		n += (mask >> slot) & 1
	return n
