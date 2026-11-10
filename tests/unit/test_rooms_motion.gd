extends TestCase
## Motion rooms: Bumper Cloud, Shutter Gates, Caterpillar Crawl, Lantern Swing,
## Stalker Rail, Pinwheel and Saw Ring.

const SUB := SimConfig.SUB
const IDS: Array[String] = ["cloud", "gates", "crawl", "swing", "stalker", "pinwheel", "sawring"]


static func sim_in_room(id: String, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
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
	assert_eq(kinds(sim_in_room("gates", 1)), ["gate", "gate"] as Array[String])
	assert_eq(kinds(sim_in_room("crawl", 1)), ["crawler", "crawler"] as Array[String])
	assert_eq(kinds(sim_in_room("swing", 1)), ["pendulum"] as Array[String])
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
	var heart := RoomDef.new("heart_test", "seasonal", 0)
	heart.skin = "heart"
	heart.hazards = RoomCatalog.find("cloud").hazards
	var hs := GameSim.new(1)
	hs.room.start(heart, 0, hs, SimRng.new(1))
	assert_eq(hs.room.hazards[0].skin, "heart")
	assert_eq(hs.room.hazards[0].kind, "bumper")


# --- Shutter Gates --------------------------------------------------------------


func test_gate_edges_kill_and_gaps_are_safe() -> void:
	var sim := sim_in_room("gates", 4)
	var g0: Hazard = sim.room.hazards[0]
	var g1: Hazard = sim.room.hazards[1]
	assert_true(g0.GAP >= 110 * SUB, "gap at least 110 px")
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
	var sim := sim_in_room("gates", 4)
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
	var sim := sim_in_room("crawl", 6)
	for h: Hazard in sim.room.hazards:
		assert_eq(h.xs.size(), 6, "six segments")
		for i in h.xs.size():
			put_bird(sim, h.xs[i], h.ys[i])
			assert_true(h.kills(sim), "segment %d kills" % i)
		put_bird(sim, 180 * SUB, 320 * SUB)
		assert_false(h.kills(sim), "the middle of the cage is safe")


func test_crawlers_walk_the_whole_loop() -> void:
	var sim := sim_in_room("crawl", 6)
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


func test_crab_skin_reaches_the_crawler() -> void:
	var crab := RoomDef.new("crab_test", "seasonal", 0)
	crab.skin = "crab"
	crab.hazards = RoomCatalog.find("crawl").hazards
	var sim := GameSim.new(1)
	sim.room.start(crab, 0, sim, SimRng.new(1))
	assert_eq(sim.room.hazards[0].skin, "crab")


# --- Lantern Swing --------------------------------------------------------------


func test_lantern_kills_and_chain_is_safe() -> void:
	var sim := sim_in_room("swing", 2)
	var p: Hazard = sim.room.hazards[0]
	put_bird(sim, p.x, p.y)
	assert_true(p.kills(sim), "the lantern kills")
	# Halfway up the chain.
	put_bird(sim, (p.x + p.PIVOT_X) / 2, (p.y + p.PIVOT_Y) / 2)
	assert_false(p.kills(sim), "the chain is safe")


func test_lantern_swings_inside_the_room() -> void:
	var sim := sim_in_room("swing", 2)
	var p: Hazard = sim.room.hazards[0]
	var low := 1 << 40
	var high := -1
	for i in p.PERIOD:
		sim.room.step(sim)
		low = mini(low, p.x)
		high = maxi(high, p.x)
		assert_true(p.x - p.RADIUS >= 40 * SUB and p.x + p.RADIUS <= 320 * SUB, "inside x")
		assert_true(p.y + p.RADIUS < SimConfig.KILL_BOTTOM, "above the floor")
	assert_true(high - low > 150 * SUB, "swings across the middle")


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


# --- Pinwheel -------------------------------------------------------------------


func test_pinwheel_blades_and_hub_kill() -> void:
	var sim := sim_in_room("pinwheel", 7)
	var r: Hazard = sim.room.hazards[0]
	put_bird(sim, r.CENTER_X, r.CENTER_Y)
	assert_true(r.kills(sim), "the hub kills")
	for i in r.BLADES:
		var a: int = r.blade_angle(i)
		var d: int = r.BLADE_LENGTH * 3 / 4
		put_bird(
			sim,
			r.CENTER_X + d * SimTrig.cos_t(a) / SimTrig.ONE,
			r.CENTER_Y + d * SimTrig.sin_t(a) / SimTrig.ONE
		)
		assert_true(r.kills(sim), "blade %d kills" % i)
		# Between this blade and the next, out near the tips.
		var mid: int = a + SimTrig.TURN / (2 * r.BLADES)
		var far := 90 * SUB
		put_bird(
			sim,
			r.CENTER_X + far * SimTrig.cos_t(mid) / SimTrig.ONE,
			r.CENTER_Y + far * SimTrig.sin_t(mid) / SimTrig.ONE
		)
		assert_false(r.kills(sim), "between blades %d and %d is safe" % [i, i + 1])
	put_bird(sim, r.CENTER_X, r.CENTER_Y - 140 * SUB)
	assert_false(r.kills(sim), "above the pinwheel is safe")


func test_pinwheel_turns_steadily() -> void:
	var sim := sim_in_room("pinwheel", 7)
	var r: Hazard = sim.room.hazards[0]
	var start: int = r.angle
	advance(sim, r.PERIOD / 4)
	var quarter := posmod((r.angle - start) * r.dir, SimTrig.TURN)
	assert_between(quarter, 250, 262, "a quarter turn in a quarter period")
	advance(sim, r.PERIOD * 3 / 4)
	assert_between(posmod(r.angle - start, SimTrig.TURN), 0, 4, "back round after a period")


# --- Saw Ring -------------------------------------------------------------------


func test_saws_kill_and_the_centre_is_safe() -> void:
	for s in 10:
		var sim := sim_in_room("sawring", s)
		var ring: Hazard = sim.room.hazards[0]
		assert_between(ring.count, 4, 6, "4 to 6 saws")
		for i in ring.count:
			put_bird(sim, ring.xs[i], ring.ys[i])
			assert_true(ring.kills(sim), "saw %d kills" % i)
		put_bird(sim, ring.CENTER_X, ring.CENTER_Y)
		assert_false(ring.kills(sim), "the centre is safe")


func test_saw_ring_breathes_on_a_schedule() -> void:
	var sim := sim_in_room("sawring", 2)
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
