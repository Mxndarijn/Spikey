extends TestCase
## Bramble Ball's variants: the classic ball, Twin Brambles, Splitting,
## Rev-Up, Curious and Heavy Bramble. Each hazard is stepped on its own here,
## with the bird put where the test needs it.

const SUB := SimConfig.SUB
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const SplittingBouncer := preload("res://sim/hazards/splitting_bouncer.gd")
const RevvingBouncer := preload("res://sim/hazards/revving_bouncer.gd")
const CuriousBouncer := preload("res://sim/hazards/curious_bouncer.gd")
const HeavyBouncer := preload("res://sim/hazards/heavy_bouncer.gd")


## A sim in Bramble Ball playing variant `id`.
static func bramble(id: String) -> GameSim:
	var index := RoomCatalog.index_of("bramble")
	for s in 200:
		var sim := GameSim.new(s)
		sim.state.room_kind = index
		sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(s + 1))
		if sim.room.variant_id() == id:
			return sim
	return null


## Steps the room's hazards `n` times without moving the bird.
static func run_hazards(sim: GameSim, n: int) -> void:
	for i in n:
		sim.room.step(sim)


func test_every_variant_has_its_ball() -> void:
	var want := {
		"classic": [Bouncer.RADIUS],
		"twin": [Bouncer.TWIN_RADIUS, Bouncer.TWIN_RADIUS],
		"split": [SplittingBouncer.BIG_RADIUS],
		"revup": [Bouncer.RADIUS],
		"curious": [Bouncer.RADIUS],
		"heavy": [HeavyBouncer.HEAVY_RADIUS],
	}
	assert_eq(RoomCatalog.find("bramble").variants.size(), want.size(), "six variants")
	for id: String in want:
		var sim := bramble(id)
		assert_true(sim != null, "%s shows up" % id)
		if sim == null:
			continue
		var radii: Array = []
		for h in sim.room.hazards:
			assert_eq(h.kind, "bouncer", "%s draws as a bouncer" % id)
			radii.append(h.radius)
		assert_eq(radii, want[id], "%s balls" % id)


func test_balls_start_away_from_the_bird() -> void:
	for v in RoomCatalog.find("bramble").variants:
		var sim := bramble(v.id)
		for h in sim.room.hazards:
			var bird_left := sim.state.x < SimConfig.WORLD_W / 2
			assert_eq(h.x > SimConfig.WORLD_W / 2, bird_left, "%s starts in the far half" % v.id)
			assert_eq(h.vx > 0, bird_left, "%s flies away from the bird" % v.id)


func test_twins_take_the_upper_and_lower_lanes() -> void:
	var mid := SimConfig.WORLD_H / 2
	for s in 30:
		var sim := GameSim.new(s)
		var upper := Bouncer.new(Bouncer.TWIN_RADIUS, Bouncer.Lane.UPPER)
		var lower := Bouncer.new(Bouncer.TWIN_RADIUS, Bouncer.Lane.LOWER)
		upper.setup(sim, SimRng.new(s))
		lower.setup(sim, SimRng.new(s))
		assert_true(upper.y < mid and upper.vy > 0, "upper ball starts high, moving down")
		assert_true(lower.y >= mid and lower.vy < 0, "lower ball starts low, moving up")
		assert_true(upper.y >= upper.top_y() and lower.y <= lower.bottom_y(), "inside the room")
		assert_true(upper.x != lower.x, "they never start on top of each other")


func test_splitting_bramble_warns_then_splits_away_from_the_bird() -> void:
	var sim := bramble("split")
	var h: SplittingBouncer = sim.room.hazards[0]
	# Keep the bird far from the ball: on the far side, out of reach.
	sim.state.x = 0
	sim.state.y = -SimConfig.WORLD_H
	run_hazards(sim, SplittingBouncer.SPLIT_AT)
	assert_false(h.is_split(), "whole before the warning")
	assert_eq(h.warn, 0, "no shaking yet")
	run_hazards(sim, SplittingBouncer.WARN - 1)
	assert_false(h.is_split(), "still whole while shaking")
	assert_true(h.warn > 0, "shaking")
	run_hazards(sim, 2)
	assert_true(h.is_split(), "split after the warning")
	assert_eq(h.radius, SplittingBouncer.SMALL_RADIUS)
	assert_eq(h.other.radius, SplittingBouncer.SMALL_RADIUS)
	assert_true(signi(h.vy) != signi(h.other.vy), "the halves fly apart")
	run_hazards(sim, 30)
	assert_true(absi(h.y - h.other.y) > 0, "and move apart")


func test_splitting_bramble_waits_while_the_bird_is_close() -> void:
	var sim := bramble("split")
	var h: SplittingBouncer = sim.room.hazards[0]
	for i in SplittingBouncer.SPLIT_AT + SplittingBouncer.WARN + 120:
		sim.state.x = h.x
		sim.state.y = h.y + SplittingBouncer.CLEAR / 2
		sim.room.step(sim)
	assert_false(h.is_split(), "never splits right next to the bird")
	sim.state.y = -SimConfig.WORLD_H
	run_hazards(sim, 1)
	assert_true(h.is_split(), "splits once the bird is clear")


func test_revup_speeds_up_per_bounce_but_stays_slower_than_the_bird() -> void:
	var sim := bramble("revup")
	var h: RevvingBouncer = sim.room.hazards[0]
	assert_eq(h.level, 0)
	assert_eq(absi(h.vx), Bouncer.SPEED_X * 6 / 10, "starts at 60%")
	var last_level := 0
	for i in 3000:
		run_hazards(sim, 1)
		assert_true(h.level >= last_level, "never slows down")
		last_level = h.level
		assert_true(absi(h.vx) < SimConfig.SPEED_X, "always slower across than the bird")
	assert_eq(h.level, RevvingBouncer.MAX_LEVEL, "reaches the cap")
	assert_eq(absi(h.vx), Bouncer.SPEED_X * 13 / 10)


func test_curious_bramble_steers_toward_the_bird_slowly() -> void:
	var sim := bramble("curious")
	var h: CuriousBouncer = sim.room.hazards[0]
	# Low in the room and still, so it has room to climb without bouncing.
	h.y = 500 * SUB
	h.vy = 0
	sim.state.y = h.y - 200 * SUB
	var start_y := h.y
	for i in 120:
		var before := h.vy
		run_hazards(sim, 1)
		assert_true(absi(h.vy) <= CuriousBouncer.MAX_VY, "climb is capped")
		assert_true(absi(h.vy - before) <= CuriousBouncer.STEER, "turns slowly")
		sim.state.y = h.y - 200 * SUB
	assert_eq(h.look, -1, "looks up at the bird")
	assert_true(h.y < start_y, "moved toward the bird")
	assert_true(CuriousBouncer.MAX_VY * 2 < -SimConfig.FLAP_VY, "a flap outclimbs it")


func test_heavy_bramble_arcs_off_the_floor_and_leaves_the_top_clear() -> void:
	var sim := bramble("heavy")
	NoExits.clear(sim)
	var h: HeavyBouncer = sim.room.hazards[0]
	var floor_y := h.bottom_y()
	var peaks: Array[int] = []
	var top := floor_y
	for i in 3000:
		var before := h.vy
		run_hazards(sim, 1)
		if h.bounces == 0:
			continue
		top = mini(top, h.y)
		if before < 0 and h.vy >= 0:
			peaks.append(floor_y - h.y)
	assert_true(h.bounces > 4, "bounces off the floor again and again")
	assert_true(peaks.size() > 4, "and peaks every time")
	for i in peaks.size():
		var want := (220 if (i % 2 == 0) else 340) * SUB
		assert_true(absi(peaks[i] - want) < 2 * SUB, "peak %d is about %d px" % [i, want / SUB])
	assert_true(top > 200 * SUB, "the top of the room stays clear")
