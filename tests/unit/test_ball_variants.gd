extends TestCase
## Variants of Caterpillar Crawl and Crab Walk (swarm, sprinters), Pumpkin
## Bounce (twin, splitting), Keepy-Uppy and Beach Ball (two balls, heavy) and
## Heart Bumpers (one big heart, orbiting hearts).

const SUB := SimConfig.SUB
const Crawler := preload("res://sim/hazards/crawler.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")
const Bumper := preload("res://sim/hazards/bumper.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const SplittingBouncer := preload("res://sim/hazards/splitting_bouncer.gd")


## A practice run in room `id` playing variant `variant`.
static func _in(id: String, variant: String, seed_value: int) -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	return GameSim.new(seed_value, def.season, index, variant)


static func _ids(id: String) -> Array[String]:
	var out: Array[String] = []
	for v in RoomCatalog.find(id).variants:
		out.append(v.id)
	return out


func test_rooms_have_the_picked_variants() -> void:
	assert_eq(_ids("crawl"), ["classic", "swarm", "sprinters"] as Array[String])
	assert_eq(_ids("crabs"), _ids("crawl"), "Crab Walk shares Caterpillar Crawl's variants")
	assert_eq(_ids("pumpkin"), ["classic", "twin", "splitting"] as Array[String])
	assert_eq(_ids("keepy"), ["classic", "two-balls"] as Array[String])
	assert_eq(_ids("beachball"), ["classic", "two", "heavy"] as Array[String])
	assert_eq(_ids("hearts"), ["classic", "one-big", "orbit"] as Array[String])
	for id: String in ["crawl", "crabs", "pumpkin", "keepy", "beachball", "hearts"]:
		assert_true(RoomCatalog.find(id).hazards.is_empty(), "%s: hazards only in variants" % id)


# --- Crawlers -------------------------------------------------------------------


func test_swarm_is_four_small_crawlers_in_pairs_on_ceiling_and_floor() -> void:
	for id: String in ["crawl", "crabs"]:
		for s in 40:
			var sim := _in(id, "swarm", 100 + s)
			var hs := sim.room.hazards
			assert_eq(hs.size(), 4, "%s: four crawlers" % id)
			for h: Hazard in hs:
				assert_true(h.seg_radius < Crawler.SEG_RADIUS, "small")
				assert_true(h.segments < Crawler.SEGMENTS, "short")
				# Whole body on its starting edge, head clear of the corner.
				var y := Crawler.TOP if h.lane == 0 else Crawler.BOTTOM
				for i in h.segments:
					assert_eq(h.ys[i], y, "%s seed %d: starts on its edge" % [id, s])
			for lane in 2:
				var lead: Hazard = hs[lane * 2]
				var tail: Hazard = hs[lane * 2 + 1]
				assert_eq(lead.lane, lane)
				assert_true(tail.trails and tail.lane == lane, "the second follows the first")
				# Head of the trailing crawler to the leader's tail: a clear gap.
				var gap: int = lead.start - (tail.start + tail.body())
				assert_eq(gap, Crawler.SWARM_GAP, "%s seed %d: one gap apart" % [id, s])


func test_swarm_pairs_stay_apart_all_the_way_round() -> void:
	var sim := _in("crawl", "swarm", 7)
	var hs := sim.room.hazards
	var touch: int = 2 * hs[0].seg_radius
	for step in Crawler.PERIMETER / Crawler.SPEED:
		sim.room.step(sim)
		for a in hs.size():
			for b in range(a + 1, hs.size()):
				for i in hs[a].segments:
					for j in hs[b].segments:
						var dx: int = hs[a].xs[i] - hs[b].xs[j]
						var dy: int = hs[a].ys[i] - hs[b].ys[j]
						assert_true(dx * dx + dy * dy > touch * touch, "step %d: apart" % step)


func test_sprinters_walk_twice_as_fast() -> void:
	var sim := _in("crabs", "sprinters", 3)
	var hs := sim.room.hazards
	assert_eq(hs.size(), 2, "two crawlers")
	var heads: Array[int] = []
	for h: Hazard in hs:
		assert_eq(h.speed, 2 * Crawler.SPEED, "double speed")
		heads.append(h.xs[0])
	sim.room.step(sim)
	for i in hs.size():
		# Along the ceiling or floor the head moves 2 px a step.
		assert_eq(absi(hs[i].xs[0] - heads[i]), 2 * SUB, "2 px a step")
	# A quick crawler starts further from the corner it walks to.
	var quick := Crawler.new(0).sprinter()
	var slow := Crawler.new(0)
	assert_true(
		Crawler.W - quick.body() - quick.start_span() > Crawler.W - slow.body() - slow.start_span(),
		"more room to the first corner"
	)


# --- Pumpkin Bounce -------------------------------------------------------------


func test_pumpkin_reuses_bramble_twin_and_splitting() -> void:
	var twin := _in("pumpkin", "twin", 5).room.hazards
	assert_eq(twin.size(), 2, "two pumpkins")
	for h: Hazard in twin:
		assert_eq(h.radius, Bouncer.TWIN_RADIUS, "smaller")
	assert_eq(twin[0].lane, Bouncer.Lane.UPPER)
	assert_eq(twin[1].lane, Bouncer.Lane.LOWER)
	var split := _in("pumpkin", "splitting", 5)
	var h: Hazard = split.room.hazards[0]
	assert_true(h is SplittingBouncer, "Splitting Bramble's ball")
	for i in SplittingBouncer.SPLIT_AT + 4 * SplittingBouncer.WARN:
		split.room.step(split)
	assert_true(h.is_split(), "it splits in two")
	assert_eq(RoomSkins.of("pumpkin"), "pumpkin")


# --- Keepy-Uppy and Beach Ball --------------------------------------------------


func test_two_balls_drop_one_after_the_other() -> void:
	for c: Array in [["keepy", "two-balls"], ["beachball", "two"]]:
		var sim := _in(c[0], c[1], 4)
		var hs := sim.room.hazards
		assert_eq(hs.size(), 2, "%s: two balls" % c[0])
		assert_eq(hs[0].waiting, 0, "the first drops at once")
		assert_eq(hs[1].waiting, KeepyBall.SECOND_DROP, "the second a while later")
		sim.room.step(sim)
		assert_true(hs[0].vy > 0, "the first falls")
		assert_eq(hs[1].vy, 0, "the second still waits")
		assert_true(hs[1].y < SimConfig.KILL_TOP, "out of sight above the ceiling")


func test_a_ball_on_the_floor_drops_in_again() -> void:
	var sim := _in("keepy", "two-balls", 4)
	sim.state.started = true
	var ball: Hazard = sim.room.hazards[0]
	ball.x = 150 * SUB
	ball.vy = KeepyBall.MAX_VY
	ball.y = SimConfig.KILL_BOTTOM - KeepyBall.RADIUS - 2 * SUB
	sim.room.step(sim)
	assert_true(ball.alive, "not gone for good")
	assert_eq(ball.waiting, KeepyBall.REDROP, "waits to drop in again")
	assert_eq(ball.x, SimConfig.WORLD_W - 150 * SUB, "over the other half")
	# Waiting, it can't be bumped.
	sim.state.x = ball.x
	sim.state.y = ball.y
	ball.touch(sim)
	assert_eq(sim.state.coins, 0, "no bump while it waits")
	for i in KeepyBall.REDROP + 60:
		sim.room.step(sim)
	assert_true(ball.y > SimConfig.KILL_TOP + KeepyBall.RADIUS, "back in the room")


## Peak height (px above the kick) of a ball kicked up with nothing in its way.
static func _bounce_height(ball: Hazard, sim: GameSim) -> int:
	ball.x = 180 * SUB
	ball.y = 500 * SUB
	ball.vx = 0
	ball.vy = -ball.kick_vy
	var top: int = ball.y
	for i in 200:
		ball.step(sim)
		top = mini(top, ball.y)
	return (500 * SUB - top) / SUB


func test_heavy_ball_bounces_low_and_short() -> void:
	var sim := _in("beachball", "heavy", 2)
	var heavy: Hazard = sim.room.hazards[0]
	assert_eq(heavy.gravity, KeepyBall.HEAVY_GRAVITY)
	var light: Hazard = _in("beachball", "classic", 2).room.hazards[0]
	var low := _bounce_height(heavy, sim)
	var high := _bounce_height(light, sim)
	assert_true(low < high / 2, "under half as high (%d px vs %d px)" % [low, high])
	assert_between(low, 40, 90, "still a real bounce")


# --- Heart Bumpers --------------------------------------------------------------


func test_one_big_heart_never_sits_on_a_bird_at_a_wall() -> void:
	var sim := _in("hearts", "one-big", 6)
	var hs := sim.room.hazards
	assert_eq(hs.size(), 1, "one heart")
	var h: Hazard = hs[0]
	assert_eq(h.radius, Bumper.BIG_RADIUS, "1.5 times the size")
	var r := SimConfig.BIRD_RADIUS
	for i in h.period:
		sim.room.step(sim)
		assert_true(h.x - h.radius > sim.room.wall_left() + 2 * r, "clear of the left wall")
		assert_true(h.x + h.radius < sim.room.wall_right() - 2 * r, "clear of the right wall")


func test_orbiting_hearts_circle_the_middle_apart() -> void:
	var sim := _in("hearts", "orbit", 6)
	var hs := sim.room.hazards
	assert_eq(hs.size(), 2, "two hearts")
	for i in hs[0].period:
		sim.room.step(sim)
		for h: Hazard in hs:
			var dx: int = (h.x - Bumper.CENTER_X) / SUB
			var dy: int = (h.y - Bumper.CENTER_Y) / SUB
			assert_between(dx * dx + dy * dy, 94 * 94, 98 * 98, "on a circle about the middle")
		var ax: int = (hs[0].x - hs[1].x) / SUB
		var ay: int = (hs[0].y - hs[1].y) / SUB
		assert_true(ax * ax + ay * ay > 180 * 180, "opposite sides")
