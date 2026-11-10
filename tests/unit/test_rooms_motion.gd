extends TestCase
## Motion rooms: Bumper Cloud, Shutter Gates, Caterpillar Crawl, Lantern Swing,
## Stalker Rail, Pinwheel and Saw Ring.

const SUB := SimConfig.SUB
const IDS: Array[String] = ["cloud", "gates", "crawl", "swing", "stalker", "pinwheel", "sawring"]


static func sim_in_room(id: String, seed_value: int, variant: String = "") -> GameSim:
	var sim := GameSim.new(seed_value, Seasons.NONE, -1, variant)
	var index := RoomCatalog.index_of(id)
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


## A sim whose bird just bounced off a wall (left or right), then the room starts.
static func sim_at_wall(id: String, seed_value: int, left: bool, y_px: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.state.x = (
		(SimConfig.BIRD_RADIUS + SUB) if left else (SimConfig.WORLD_W - SimConfig.BIRD_RADIUS - SUB)
	)
	sim.state.vx = SimConfig.SPEED_X if left else -SimConfig.SPEED_X
	sim.state.y = y_px * SUB
	var index := RoomCatalog.index_of(id)
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


static func kinds(sim: GameSim) -> Array[String]:
	var out: Array[String] = []
	for h in sim.room.hazards:
		out.append(h.kind)
	return out


static func any_kills(sim: GameSim) -> bool:
	for h in sim.room.hazards:
		if h.alive and h.kills(sim):
			return true
	return false


static func put_bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y


static func advance(sim: GameSim, steps: int) -> void:
	for i in steps:
		sim.room.step(sim)


func test_rooms_are_in_the_catalog_in_order() -> void:
	var last := -1
	for id in IDS:
		var i := RoomCatalog.index_of(id)
		assert_true(i > last, "%s is after the previous motion room" % id)
		last = i
	assert_eq(RoomCatalog.find("cloud").from_score, 10)
	assert_eq(RoomCatalog.find("gates").from_score, 20)
	assert_eq(RoomCatalog.find("crawl").from_score, 30)
	assert_eq(RoomCatalog.find("swing").group, "mid")
	assert_eq(RoomCatalog.find("stalker").from_score, 40)
	assert_eq(RoomCatalog.find("pinwheel").from_score, 40)
	assert_eq(RoomCatalog.find("sawring").group, "late")
	assert_eq(RoomCatalog.find("sawring").from_score, 80)
	assert_eq(RoomCatalog.find("sawring").weight, 8)


func test_rooms_spawn_their_hazards() -> void:
	var clouds := kinds(sim_in_room("cloud", 1))
	assert_true(clouds.size() in [1, 2], "one cloud or two")
	assert_eq(clouds[0], "bumper")
	var gates := kinds(sim_in_room("gates", 1))
	assert_true(gates.size() in [1, 2], "two gates, or one small one")
	assert_eq(gates[0], "gate")
	var crawlers := kinds(sim_in_room("crawl", 1))
	assert_true(crawlers.size() in [2, 4], "two crawlers, or a swarm of four")
	for k in crawlers:
		assert_eq(k, "crawler")
	var lanterns := kinds(sim_in_room("swing", 1))
	assert_true(lanterns.size() in [1, 3], "one lantern hazard, or three chimes")
	assert_eq(lanterns[0], "pendulum")
	assert_eq(kinds(sim_in_room("stalker", 1)), ["stalker"] as Array[String])
	assert_eq(kinds(sim_in_room("pinwheel", 1)), ["rotor"] as Array[String])
	assert_eq(kinds(sim_in_room("sawring", 1)), ["saw_ring"] as Array[String])


## Nothing kills a bird that just bounced off either wall, at any height, for
## the first steps of the room.
func test_nothing_spawns_on_the_bird() -> void:
	for id in IDS:
		for s in 12:
			for left in [true, false]:
				for y_px in range(70, 580, 30):
					var sim := sim_at_wall(id, s * 7 + 3, left, y_px)
					assert_false(any_kills(sim), "%s seed %d y %d: clear at start" % [id, s, y_px])


func test_motion_is_deterministic() -> void:
	for id in IDS:
		var a := sim_in_room(id, 42)
		var b := sim_in_room(id, 42)
		advance(a, 333)
		advance(b, 333)
		assert_eq(a.room.checksum(1), b.room.checksum(1), "%s replays the same" % id)
		var c := sim_in_room(id, 42)
		advance(c, 100)
		assert_ne(c.room.checksum(1), a.room.checksum(1), "%s moves" % id)


func test_every_motion_room_runs_with_a_bot() -> void:
	for id in IDS:
		var sim := sim_in_room(id, 5)
		var bot := SimRng.new(5)
		sim.step(true)
		for i in 600:
			if sim.is_over():
				sim = sim_in_room(id, 5 + i)
				sim.step(true)
			sim.step(SimBots.random_tapper(sim, bot, 14))
		assert_true(sim.room.t >= 0, "%s ran" % id)


# --- Bumper Cloud ---------------------------------------------------------------


func test_cloud_is_safe_but_bounces_the_bird() -> void:
	var sim := sim_in_room("cloud", 3)
	var cloud: Hazard = sim.room.hazards[0]
	# Bird just left of the cloud's centre and moving right, slightly above it.
	put_bird(sim, cloud.x - 10 * SUB, cloud.y - 5 * SUB)
	sim.state.vx = SimConfig.SPEED_X
	sim.state.vy = 0
	assert_false(cloud.kills(sim), "a cloud never kills")
	cloud.touch(sim)
	assert_eq(sim.state.vy, -GameSim.BUMP_VY, "shoved up hard")
	assert_eq(sim.state.vx, -SimConfig.SPEED_X, "sent back the way it came")
	# Away from the cloud nothing happens.
	put_bird(sim, cloud.x + 120 * SUB, cloud.y)
	sim.state.vy = 0
	cloud.touch(sim)
	assert_eq(sim.state.vy, 0, "no bump at a distance")


func test_cloud_follows_its_loop_and_heart_skin() -> void:
	var sim := sim_in_room("cloud", 8)
	var cloud: Hazard = sim.room.hazards[0]
	var seen := {}
	for i in 600:
		sim.room.step(sim)
		assert_between(cloud.x, 40 * SUB, 320 * SUB, "cloud x in the room")
		assert_between(cloud.y, 100 * SUB, 540 * SUB, "cloud y in the room")
		seen[cloud.x / (20 * SUB) * 100 + cloud.y / (20 * SUB)] = true
	assert_true(seen.size() > 20, "the cloud travels")
	var hs := GameSim.new(1)
	hs.room.start(RoomCatalog.find("hearts"), 0, hs, SimRng.new(1))
	assert_eq(hs.room.hazards[0].kind, "bumper")
	assert_eq(RoomSkins.of("hearts"), "heart", "Heart Bumpers draw the bumper as a heart")


# --- Shutter Gates --------------------------------------------------------------


func test_gate_edges_kill_and_gaps_are_safe() -> void:
	var sim := sim_in_room("gates", 4, "classic")
	var g0: Hazard = sim.room.hazards[0]
	var g1: Hazard = sim.room.hazards[1]
	assert_true(g0.gap_size >= 110 * SUB, "gap at least 110 px")
	assert_eq(g0.period, g1.period, "the columns move together")
	assert_true(g1.follows and g1.partner == g0, "the second follows the first")
	# A moment behind: the two gaps stay close, like one moving tunnel.
	for i in g0.period:
		sim.room.step(sim)
		assert_true(absi(g0.gap_y - g1.gap_y) <= 40 * SUB, "gaps stay close")
	for g: Hazard in [g0, g1]:
		put_bird(sim, g.x, g.gap_y)
		assert_false(g.kills(sim), "the gap's middle is safe")
		put_bird(sim, g.x, g.gap_top() - 5 * SUB)
		assert_true(g.kills(sim), "the upper bar kills")
		put_bird(sim, g.x, g.gap_bottom() + 5 * SUB)
		assert_true(g.kills(sim), "the lower bar kills")
		put_bird(sim, g.x - 40 * SUB, g.gap_top() - 40 * SUB)
		assert_false(g.kills(sim), "beside the bar is safe")


func test_gate_gaps_slide() -> void:
	var sim := sim_in_room("gates", 4, "classic")
	var g: Hazard = sim.room.hazards[0]
	var low := 1 << 40
	var high := -1
	for i in g.period:
		sim.room.step(sim)
		low = mini(low, g.gap_y)
		high = maxi(high, g.gap_y)
		assert_true(g.gap_top() - SimConfig.KILL_TOP >= 40 * SUB, "gap clear of the ceiling")
		assert_true(SimConfig.KILL_BOTTOM - g.gap_bottom() >= 40 * SUB, "gap clear of the floor")
	assert_true(high - low > 300 * SUB, "the gap travels up and down")


# --- Caterpillar Crawl ----------------------------------------------------------


func test_crawler_segments_kill_and_the_middle_is_safe() -> void:
	var index := RoomCatalog.index_of("crawl")
	for v in RoomCatalog.all()[index].variants:
		var sim := GameSim.new(6, Seasons.NONE, index, v.id)
		for h: Hazard in sim.room.hazards:
			assert_eq(h.xs.size(), h.segments, "%s: every segment placed" % v.id)
			for i in h.xs.size():
				put_bird(sim, h.xs[i], h.ys[i])
				assert_true(h.kills(sim), "%s: segment %d kills" % [v.id, i])
			put_bird(sim, 180 * SUB, 320 * SUB)
			assert_false(h.kills(sim), "%s: the middle of the cage is safe" % v.id)


func test_crawlers_walk_the_whole_loop() -> void:
	var sim := GameSim.new(6, Seasons.NONE, RoomCatalog.index_of("crawl"), "classic")
	var h: Hazard = sim.room.hazards[0]
	var walls := {}
	for i in h.PERIMETER / h.SPEED:
		sim.room.step(sim)
		var x: int = h.xs[0]
		var y: int = h.ys[0]
		assert_between(x, 40 * SUB, 320 * SUB, "head x in the cage")
		assert_true(y - h.SEG_RADIUS > SimConfig.KILL_TOP, "below the ceiling line")
		assert_true(y + h.SEG_RADIUS < SimConfig.KILL_BOTTOM, "above the floor line")
		if y == h.TOP:
			walls["ceiling"] = true
		if y == h.BOTTOM:
			walls["floor"] = true
		if x == h.LEFT:
			walls["left"] = true
		if x == h.RIGHT:
			walls["right"] = true
	assert_eq(walls.size(), 4, "visits ceiling, floor and both walls")


func test_crab_walk_draws_its_crawlers_as_crabs() -> void:
	var sim := GameSim.new(1)
	sim.room.start(RoomCatalog.find("crabs"), 0, sim, SimRng.new(1))
	assert_eq(sim.room.hazards[0].kind, "crawler")
	assert_eq(RoomSkins.of("crabs"), "crab")


# --- Stalker Rail ---------------------------------------------------------------


func test_stalker_rides_the_wall_ahead_and_kills() -> void:
	var sim := sim_at_wall("stalker", 3, true, 300)
	var s: Hazard = sim.room.hazards[0]
	sim.room.step(sim)
	assert_eq(s.side, 1, "on the right wall while the bird flies right")
	put_bird(sim, SimConfig.WORLD_W - SimConfig.BIRD_RADIUS - 2 * SUB, s.y)
	assert_true(s.kills(sim), "the spikes kill at the wall")
	put_bird(sim, SimConfig.WORLD_W / 2, s.y)
	assert_false(s.kills(sim), "the middle of the room is safe")
	sim.state.vx = -SimConfig.SPEED_X
	sim.room.step(sim)
	assert_eq(s.side, 0, "switches to the left wall when the bird turns")
	assert_eq(s.x, sim.room.wall_left())
	put_bird(sim, SimConfig.BIRD_RADIUS + 2 * SUB, s.y)
	assert_true(s.kills(sim), "kills on the left wall")


func test_stalker_chases_at_a_capped_speed() -> void:
	var sim := sim_at_wall("stalker", 9, true, 300)
	var s: Hazard = sim.room.hazards[0]
	s.y = s.MIN_Y
	sim.state.y = s.MAX_Y
	var before: int = s.y
	sim.room.step(sim)
	assert_eq(s.y - before, s.MAX_SPEED, "moves at most MAX_SPEED a step")
	for i in 2000:
		sim.room.step(sim)
	assert_eq(s.y, s.MAX_Y, "reaches the bird's height in the end")
	sim.state.y = 0
	for i in 2000:
		sim.room.step(sim)
	assert_eq(s.y, s.MIN_Y, "stays on the rail")


# --- Saw Ring -------------------------------------------------------------------


## The classic ring (the other variants: test_orbit_variants.gd).
static func classic_ring(seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.forced_variant = "classic"
	var index := RoomCatalog.index_of("sawring")
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


func test_saws_kill_and_the_centre_is_safe() -> void:
	for s in 10:
		var sim := classic_ring(s)
		var ring: Hazard = sim.room.hazards[0]
		assert_between(ring.count, 4, 6, "4 to 6 saws")
		for i in ring.count:
			put_bird(sim, ring.xs[i], ring.ys[i])
			assert_true(ring.kills(sim), "saw %d kills" % i)
		put_bird(sim, ring.CENTER_X, ring.CENTER_Y)
		assert_false(ring.kills(sim), "the centre is safe")


func test_saw_ring_breathes_on_a_schedule() -> void:
	var sim := classic_ring(2)
	var ring: Hazard = sim.room.hazards[0]
	assert_eq(ring.radius, ring.RING_MIN, "starts small")
	var sizes := {}
	for i in ring.CYCLE:
		sim.room.step(sim)
		sizes[ring.radius] = true
		for k in ring.count:
			assert_true(ring.xs[k] - ring.SAW_RADIUS >= 40 * SUB, "saw inside x")
			assert_true(ring.xs[k] + ring.SAW_RADIUS <= 320 * SUB, "saw inside x")
	assert_true(sizes.has(ring.RING_MAX), "reaches full size")
	assert_true(sizes.size() > 30, "grows and shrinks smoothly")
	assert_eq(ring.radius_at(0), ring.radius_at(ring.CYCLE), "the schedule repeats")
	# Grow and shrink take 1.5 s each (90 steps), the holds 1 s.
	var hold: int = ring.HOLD
	var move: int = ring.MOVE
	assert_eq(move, 90, "grow and shrink take 1.5 s each")
	assert_eq(ring.radius_at(hold), ring.RING_MIN, "growth starts after the small hold")
	assert_true(ring.radius_at(hold + 60) < ring.RING_MAX, "still growing after 1 s")
	assert_eq(ring.radius_at(hold + move), ring.RING_MAX, "full size after 1.5 s")
	assert_true(ring.radius_at(2 * hold + move + 60) > ring.RING_MIN, "still shrinking after 1 s")
