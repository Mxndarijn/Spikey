extends TestCase
## Room pacing (RoomPacing: weight curves over the score) and the room deck
## (RoomCatalog.pick_next: a shuffle bag).

const TIER_ORDER := ["EASY", "STEADY", "MIDDLE", "HARD", "HARDER", "HARDEST"]
const TIER_CURVES := [
	RoomPacing.EASY,
	RoomPacing.STEADY,
	RoomPacing.MIDDLE,
	RoomPacing.HARD,
	RoomPacing.HARDER,
	RoomPacing.HARDEST,
]


func test_curve_values() -> void:
	var easy := PackedInt32Array(RoomPacing.EASY)
	assert_eq(RoomPacing.weight(easy, 0), 0, "not before the unlock")
	assert_eq(RoomPacing.weight(easy, 9), 0, "not before the unlock")
	assert_eq(RoomPacing.weight(easy, 10), 10, "full at the unlock")
	assert_eq(RoomPacing.weight(easy, 60), 10, "full until the fade")
	# 10 + (1 - 10) * 45 / 90 = 10 - 4 (integer division toward zero)
	assert_eq(RoomPacing.weight(easy, 105), 6, "halfway down the fade")
	assert_eq(RoomPacing.weight(easy, 150), 1, "the floor")
	assert_eq(RoomPacing.weight(easy, 5000), 1, "the floor holds")
	var hard := PackedInt32Array(RoomPacing.HARD)
	assert_eq(RoomPacing.weight(hard, 49), 0)
	assert_eq(RoomPacing.weight(hard, 50), 4, "ramps in")
	assert_eq(RoomPacing.weight(hard, 75), 8, "4 + 8 * 25 / 50")
	assert_eq(RoomPacing.weight(hard, 100), 12)
	assert_eq(RoomPacing.weight(hard, 150), 13, "12 + 2 * 50 / 100")
	assert_eq(RoomPacing.weight(hard, 900), 14, "the last weight holds")
	assert_eq(RoomPacing.weight(PackedInt32Array(), 100), 0, "no curve: never")


func test_every_tier_room_exists_and_unlocks_at_its_curve() -> void:
	for id: String in RoomPacing.TIERS:
		var def := RoomCatalog.find(id)
		assert_true(def != null, "%s is a room" % id)
		if def == null:
			continue
		assert_false(def.boss, "%s: bosses come only through pick_boss" % id)
		assert_eq(def.from_score, def.pace[0], "%s unlocks where its curve starts" % id)
		assert_true(def.from_score >= 10, "%s never before the first exit" % id)
	assert_true(RoomCatalog.find("open").pace.is_empty(), "the first room is never picked")
	for b in RoomCatalog.bosses():
		assert_true(RoomCatalog.all()[b].pace.is_empty(), "bosses have no curve")


func test_tiers_unlock_and_grow_in_order() -> void:
	var last_from := 0
	for t in TIER_ORDER.size():
		var name: String = TIER_ORDER[t]
		var tier: Array = TIER_CURVES[t]
		assert_true(tier[0] >= last_from, "%s unlocks no earlier than the tier before" % name)
		last_from = tier[0]
		assert_eq(tier.size() % 2, 0, "%s: score, weight pairs" % name)
		for i in range(2, tier.size(), 2):
			assert_true(tier[i] > tier[i - 2], "%s: scores go up" % name)
	# Late in a run the hardest tier weighs most, the easiest least.
	for score in [200, 400]:
		var prev := -1
		for t in TIER_ORDER.size():
			var w := RoomPacing.weight(PackedInt32Array(TIER_CURVES[t]), score)
			assert_true(
				w >= prev, "%s weighs no less than the tier before at %d" % [TIER_ORDER[t], score]
			)
			prev = w


func test_rooms_that_change_the_controls_wait_for_the_floor() -> void:
	for id: String in RoomPacing.CONTROL_ROOMS:
		var def := RoomCatalog.find(id)
		var unlock := maxi(RoomPacing.TIERS[id][0], RoomPacing.CONTROL_FLOOR)
		assert_eq(def.from_score, unlock, "%s unlocks at the floor or its tier's unlock" % id)
		assert_eq(def.weight_at(RoomPacing.CONTROL_FLOOR - 1), 0, id)
		var tier := PackedInt32Array(RoomPacing.TIERS[id])
		for i in range(1, tier.size(), 2):
			tier[i] *= RoomPacing.OTHERS_SCALE
		for score in [40, 70, 150, 300]:
			assert_eq(
				def.weight_at(score), RoomPacing.weight(tier, score), "%s keeps its curve" % id
			)
	var steady := PackedInt32Array(RoomPacing.STEADY)
	assert_eq(RoomPacing.floored(steady, 30), PackedInt32Array([30, 8, 40, 10, 100, 10, 250, 2]))


func test_seasonal_rooms_are_boosted_but_bonus_rooms_are_not() -> void:
	var hearts := RoomCatalog.find("hearts")
	assert_eq(hearts.weight_at(30), 37, "a middle seasonal room: 5 * 5 * 3 / 2")
	assert_eq(RoomCatalog.find("crawl").weight_at(30), 25, "a middle room: 5 * 5")
	for id: String in ["beachball", "countdown", "garden", "slowmo"]:
		assert_eq(RoomCatalog.find(id).weight_at(300), RoomPacing.BONUS[1], "%s occasional" % id)


func test_a_drawn_room_comes_back_only_after_a_refill() -> void:
	var rng := SimRng.new(4)
	var state := _state(0)
	var current := RoomCatalog.first_index()
	var refills := 0
	for i in 2000:
		state.score = 10 + (i / 4) * 10 % 600
		var before := state.copy()
		var next := RoomCatalog.pick_next(rng, state, current, Seasons.NONE)
		assert_ne(next, current, "never the current room")
		assert_true(RoomCatalog.drawn(state, next), "the pick is marked drawn")
		if RoomCatalog.drawn(before, next):
			# Only a refill brings a drawn room back: the bag then holds only
			# the room just left and this one.
			var fresh := _state(0)
			RoomCatalog.mark_drawn(fresh, current)
			RoomCatalog.mark_drawn(fresh, next)
			assert_eq(state.deck_lo, fresh.deck_lo, "a repeat only after a refill (%d)" % i)
			assert_eq(state.deck_hi, fresh.deck_hi)
			refills += 1
		current = next
	assert_true(refills > 10, "the bag refills (%d)" % refills)


func test_rooms_rarely_come_back_soon() -> void:
	var rng := SimRng.new(8)
	var state := _state(200)
	var current := RoomCatalog.first_index()
	var last := {}
	var gaps: Array[int] = []
	for i in 3000:
		var next := RoomCatalog.pick_next(rng, state, current, Seasons.NONE)
		if last.has(next):
			gaps.append(i - last[next])
		last[next] = i
		current = next
	gaps.sort()
	var median := gaps[gaps.size() / 2]
	assert_true(median >= 15, "a room comes back after %d picks (median)" % median)
	assert_true(gaps[0] > RoomCatalog.RECENT_ROOMS, "never within the last picks (%d)" % gaps[0])


## Runs as the game plays them (tools/room_odds.gd): a pick every
## POINTS_PER_ROOM points, a boss every BOSS_EVERY, arrival heights spread over
## the exit range, so forks and arrival skips narrow some picks.
func test_no_room_comes_back_within_the_last_picks() -> void:
	var low := SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE
	var high := SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	var picks := 0
	for run in 40:
		var rng := SimRng.new(3000 + run)
		var heights := SimRng.new(7000 + run)
		var state := _state(0)
		var current := RoomCatalog.first_index()
		var seen: Array[int] = []
		for score in range(SimConfig.POINTS_PER_ROOM, 800, SimConfig.POINTS_PER_ROOM):
			if score % SimConfig.BOSS_EVERY == 0:
				current = RoomCatalog.bosses()[0]
				continue
			state.score = score
			state.anchor_y = low + heights.next_below(high - low)
			current = RoomCatalog.pick_next(rng, state, current, Seasons.NONE)
			var from := maxi(0, seen.size() - RoomCatalog.RECENT_ROOMS)
			assert_false(
				current in seen.slice(from),
				"run %d at %d: %s again" % [run, score, RoomCatalog.all()[current].id]
			)
			assert_eq(RoomCatalog.recent(state, 0), current, "the pick is the last one")
			seen.append(current)
			picks += 1
	assert_true(picks > 2000, "%d picks" % picks)


func test_the_last_picks_shrink_when_no_other_room_fits() -> void:
	# At 10 only the Easy rooms are open: with all of them among the last
	# picks, the window drops the newest ones until the oldest is free.
	var easy: Array[int] = []
	for i in RoomCatalog.all().size():
		if RoomCatalog.all()[i].weight_at(10) > 0 and i != RoomCatalog.first_index():
			easy.append(i)
	assert_eq(easy.size(), 7, "the Easy rooms")
	for seed_value in 50:
		var state := _state(10)
		for i in easy:
			RoomCatalog.remember(state, i)
		var next := RoomCatalog.pick_next(SimRng.new(seed_value), state, -1, Seasons.NONE)
		assert_eq(next, easy[0], "the oldest pick is the only one free")
		assert_eq(RoomCatalog.recent(state, 0), easy[0], "and it is the last pick now")
		assert_eq(RoomCatalog.recent(state, 1), easy[6])
	# The current room (the newest pick) stays out however small the window.
	var got := {}
	for seed_value in 50:
		var state := _state(10)
		for i in easy:
			RoomCatalog.remember(state, i)
		var next := RoomCatalog.pick_next(SimRng.new(seed_value), state, easy[6], Seasons.NONE)
		got[next] = true
	assert_eq(got.size(), 1, "with the current room out too only the oldest is left")
	assert_true(got.has(easy[0]))


func test_the_last_picks_keep_only_the_newest() -> void:
	var state := _state(0)
	assert_eq(RoomCatalog.recent(state, 0), -1, "none yet")
	for i in RoomCatalog.RECENT_ROOMS + 3:
		RoomCatalog.remember(state, 100 + i)
	for k in RoomCatalog.RECENT_ROOMS:
		assert_eq(RoomCatalog.recent(state, k), 100 + RoomCatalog.RECENT_ROOMS + 2 - k)
	assert_eq(RoomCatalog.recent(state, RoomCatalog.RECENT_ROOMS), -1, "the oldest dropped out")
	assert_true(state.recent_rooms > 0, "fits in one word")
	assert_eq(state.copy().recent_rooms, state.recent_rooms, "a copy keeps them")
	assert_ne(_state(0).checksum(), state.checksum(), "they are in the checksum")
	assert_true(RoomCatalog.all().size() < (1 << RoomCatalog.RECENT_BITS), "every room index fits")


func test_a_new_unlock_joins_the_bag() -> void:
	# Every room open at 20 but two is drawn; at 30 the middle rooms unlock.
	var keep: Array[int] = [RoomCatalog.index_of("cloud"), RoomCatalog.index_of("belt")]
	var newcomers := {}
	for seed_value in 200:
		var state := _state(30)
		for i in RoomCatalog.all().size():
			var def: RoomDef = RoomCatalog.all()[i]
			if def.weight_at(20) > 0 and def.season == Seasons.NONE and not i in keep:
				RoomCatalog.mark_drawn(state, i)
		var next := RoomCatalog.pick_next(SimRng.new(seed_value), state, -1, Seasons.NONE)
		var picked: RoomDef = RoomCatalog.all()[next]
		assert_true(next in keep or picked.from_score == 30, "%s is still in the bag" % picked.id)
		if picked.from_score == 30:
			newcomers[picked.id] = true
	assert_true(newcomers.size() >= 4, "new rooms are drawn: %s" % ", ".join(newcomers.keys()))


func test_the_pick_is_deterministic_and_the_deck_is_state() -> void:
	var a := _run_picks(77)
	var b := _run_picks(77)
	assert_eq(a, b, "same seed, same rooms")
	assert_ne(a, _run_picks(78), "another seed, other rooms")
	var state := _state(100)
	RoomCatalog.mark_drawn(state, 5)
	RoomCatalog.mark_drawn(state, 70)
	var copy := state.copy()
	assert_eq(copy.deck_lo, state.deck_lo, "a copy keeps the deck")
	assert_eq(copy.deck_hi, 1 << (70 - RoomCatalog.DECK_BITS), "room 70 is in the second word")
	assert_true(RoomCatalog.drawn(copy, 70) and not RoomCatalog.drawn(copy, 6))
	var other := _state(100)
	assert_ne(other.checksum(), state.checksum(), "the deck is in the checksum")
	assert_true(RoomCatalog.all().size() <= 2 * RoomCatalog.DECK_BITS, "the deck holds every room")


func test_difficulty_rises_with_the_score() -> void:
	var bands: Array[int] = [10, 50, 100, 200]
	var means: Array[int] = []
	for band in bands:
		var rng := SimRng.new(band)
		var state := _state(band)
		var current := RoomCatalog.first_index()
		var sum := 0
		var n := 0
		for i in 400:
			state.score = band + (i % 5) * 10
			current = RoomCatalog.pick_next(rng, state, current, Seasons.NONE)
			var def: RoomDef = RoomCatalog.all()[current]
			if def.group == "bonus":
				continue
			sum += 100 * _tier_rank(def.id)
			n += 1
		means.append(sum / n)
	for i in range(1, means.size()):
		assert_true(
			means[i] > means[i - 1],
			"harder rooms at %d than at %d: %s" % [bands[i], bands[i - 1], means]
		)


func _tier_rank(id: String) -> int:
	var tier: Array = RoomPacing.TIERS[id]
	for i in TIER_CURVES.size():
		if TIER_CURVES[i] == tier:
			return i
	return -1


func _run_picks(seed_value: int) -> Array[int]:
	var rng := SimRng.new(seed_value)
	var state := _state(10)
	var current := RoomCatalog.first_index()
	var out: Array[int] = []
	for i in 60:
		state.score = 10 + i * 10
		current = RoomCatalog.pick_next(rng, state, current, Seasons.WINTER)
		out.append(current)
	out.append(state.deck_lo)
	out.append(state.deck_hi)
	return out


static func _state(score: int) -> SimState:
	var state := SimState.new()
	state.score = score
	state.anchor_y = SimConfig.WORLD_H
	return state
