extends TestCase
## Variants of Saw Ring, Bat Loop, Firework Burst and Cupid Lanes.

const SUB := SimConfig.SUB
const SawRing := preload("res://sim/hazards/saw_ring.gd")
const Mover := preload("res://sim/hazards/mover.gd")
const Firework := preload("res://sim/hazards/firework.gd")
const Dart := preload("res://sim/hazards/dart.gd")


## A sim in room `id` playing variant `variant`, before the first tap.
static func sim_in(id: String, variant: String, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.forced_variant = variant
	var index := RoomCatalog.index_of(id)
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	assert(sim.room.variant_id() == variant)
	return sim


static func ids(id: String) -> Array[String]:
	var out: Array[String] = []
	for v: RoomVariant in RoomCatalog.find(id).variants:
		out.append(v.id)
	return out


static func put_bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y
	sim.state.anchor_y = sim.state.y


func test_rooms_have_their_variants() -> void:
	assert_eq(
		ids("sawring"), ["classic", "two-rings", "off-centre", "oval", "pair"] as Array[String]
	)
	assert_eq(ids("bats"), ["classic", "wide", "pair"] as Array[String])
	assert_eq(ids("fireworks"), ["classic", "double", "cross"] as Array[String])
	assert_eq(ids("cupid"), ["classic", "double", "slow-volley"] as Array[String])
	for id: String in ["sawring", "bats", "fireworks", "cupid"]:
		assert_true(RoomCatalog.find(id).hazards.is_empty(), "%s: hazards only in variants" % id)


# --- Saw Ring -------------------------------------------------------------------


func test_classic_saw_ring_is_the_shared_default() -> void:
	var ring: Hazard = sim_in("sawring", "classic", 3).room.hazards[0]
	var plain := SawRing.new()
	for field: String in [
		"center_x", "ring_min", "ring_max", "saw_radius", "period", "inner_count"
	]:
		assert_eq(ring.get(field), plain.get(field), "classic keeps %s" % field)
	assert_between(ring.count, 4, 5, "4 or 5 saws")
	assert_eq(ring.arrival_clear(), SawRing.ARRIVAL_CLEAR, "same portal clearance")


func test_every_saw_stays_inside_and_kills() -> void:
	for v: String in ids("sawring"):
		for s in 4:
			var sim := sim_in("sawring", v, s)
			var ring: Hazard = sim.room.hazards[0]
			for i in ring.xs.size():
				put_bird(sim, ring.xs[i], ring.ys[i])
				assert_true(ring.kills(sim), "%s saw %d kills" % [v, i])
			for step in SawRing.CYCLE + 20:
				sim.room.step(sim)
				for i in ring.xs.size():
					var r: int = ring.saw_r(i)
					assert_true(ring.xs[i] - r >= 70 * SUB, "%s: saw right of x 70" % v)
					assert_true(ring.xs[i] + r <= 290 * SUB, "%s: saw left of x 290" % v)


func test_two_rings_turn_opposite_ways_without_touching() -> void:
	var sim := sim_in("sawring", "two-rings", 5)
	var ring: Hazard = sim.room.hazards[0]
	assert_eq(ring.count, 3, "three big saws")
	assert_eq(ring.inner_count, 2, "two small ones inside")
	assert_true(ring.inner_saw < ring.saw_radius, "inner saws are smaller")
	var cx: int = ring.center_x
	var cy: int = ring.center_y
	var before := [ring.xs[0] - cx, ring.ys[0] - cy, ring.xs[3] - cx, ring.ys[3] - cy]
	for step in 2 * SawRing.CYCLE:
		sim.room.step(sim)
		for o in ring.count:
			for i in range(ring.count, ring.xs.size()):
				var dx: int = ring.xs[o] - ring.xs[i]
				var dy: int = ring.ys[o] - ring.ys[i]
				var gap: int = ring.saw_r(o) + ring.saw_r(i)
				assert_true(dx * dx + dy * dy > gap * gap, "inner and outer saws never touch")
		if step == 9:
			# Turn direction of each ring: sign of the cross product.
			var outer: int = before[0] * (ring.ys[0] - cy) - before[1] * (ring.xs[0] - cx)
			var inner: int = before[2] * (ring.ys[3] - cy) - before[3] * (ring.xs[3] - cx)
			assert_true(outer * inner < 0, "the rings turn opposite ways")


func test_off_centre_ring_sits_left_of_the_middle() -> void:
	var sim := sim_in("sawring", "off-centre", 2)
	var ring: Hazard = sim.room.hazards[0]
	assert_true(ring.center_x < SawRing.CENTER_X - 30 * SUB, "well left of the middle")
	for step in SawRing.CYCLE:
		sim.room.step(sim)
		for i in ring.count:
			assert_true(ring.xs[i] < SawRing.CENTER_X + 40 * SUB, "the right side stays open")


func test_oval_is_wide_not_tall() -> void:
	var sim := sim_in("sawring", "oval", 4)
	var ring: Hazard = sim.room.hazards[0]
	var wide := 0
	var tall := 0
	for step in SawRing.CYCLE + SawRing.PERIOD:
		sim.room.step(sim)
		for i in ring.count:
			wide = maxi(wide, absi(ring.xs[i] - ring.center_x))
			tall = maxi(tall, absi(ring.ys[i] - ring.center_y))
	assert_true(wide >= SawRing.RING_MAX - SUB, "as wide as the classic ring")
	assert_true(tall <= SawRing.RING_MAX / 2, "half as tall")
	assert_true(tall >= SawRing.RING_MAX / 2 - SUB, "but still an oval")


func test_pair_is_two_faster_saws() -> void:
	var sim := sim_in("sawring", "pair", 6)
	var ring: Hazard = sim.room.hazards[0]
	assert_eq(ring.count, 2, "two saws")
	assert_true(ring.period < SawRing.PERIOD, "a faster lap")
	assert_eq(ring.xs[0] - ring.center_x, -(ring.xs[1] - ring.center_x), "opposite each other")
	# The saws move slower than the bird.
	var x: int = ring.xs[0]
	var y: int = ring.ys[0]
	for step in SawRing.CYCLE:
		sim.room.step(sim)
		var d := maxi(absi(ring.xs[0] - x), absi(ring.ys[0] - y))
		assert_true(d < SimConfig.SPEED_X, "a saw moves under 4 px a step")
		x = ring.xs[0]
		y = ring.ys[0]


## Out of a portal no saw reaches the bird's height while it holds height.
func test_saw_rings_keep_off_a_bird_out_of_a_portal() -> void:
	for v: String in ids("sawring"):
		for y_px in range(120, 521, 20):
			var sim := sim_in("sawring", v, y_px)
			sim.state.started = true
			sim.state.y = y_px * SUB
			sim.state.anchor_y = sim.state.y
			var ring: Hazard = sim.room.hazards[0]
			ring.setup(sim, SimRng.new(y_px))
			for step in SimConfig.ARRIVAL_HOLD:
				ring.t += 1
				ring.step(sim)
				for i in ring.xs.size():
					var reach: int = ring.saw_r(i) + SimConfig.BIRD_RADIUS
					assert_true(
						absi(ring.ys[i] - sim.state.y) > reach,
						"%s at %d px: saw %d off the bird's height" % [v, y_px, i]
					)


# --- Bat Loop -------------------------------------------------------------------


func test_wide_loop_is_bigger_faster_and_fair() -> void:
	var sim := sim_in("bats", "wide", 2)
	var m: Hazard = sim.room.hazards[0]
	assert_eq(m.count, 3, "three bats")
	assert_true(m.loop_w > Mover.LOOP_W and m.loop_h > Mover.LOOP_H, "a bigger eight")
	assert_true(m.loop_period < Mover.LOOP_PERIOD, "a faster lap")
	_check_bats(sim, m, "wide")


func test_chasing_pair_speeds_up_and_stops_at_the_cap() -> void:
	var sim := sim_in("bats", "pair", 4)
	var m: Hazard = sim.room.hazards[0]
	assert_eq(m.count, 2, "two bats")
	assert_true(m.chase, "one chases")
	var p: int = m.loop_period
	assert_eq(m.chase_tenths(0), 0)
	var lap_tenths := p * Mover.CHASE_DEN
	# Each lap is quicker than the one before, until the cap.
	var laps: Array[int] = []
	var last := 0
	for tick in 4000:
		if m.chase_tenths(tick + 1) / lap_tenths > m.chase_tenths(tick) / lap_tenths:
			laps.append(tick + 1 - last)
			last = tick + 1
	assert_true(laps.size() >= 6, "laps flown")
	for k in Mover.CHASE_LAPS:
		assert_true(laps[k + 1] < laps[k], "lap %d is quicker" % (k + 1))
	var top := p * Mover.CHASE_DEN / (Mover.CHASE_DEN + Mover.CHASE_LAPS * Mover.CHASE_STEP)
	for k in range(Mover.CHASE_LAPS + 1, laps.size()):
		assert_between(laps[k], top - 1, top + 1, "capped at 130%")
	_check_bats(sim, m, "pair")


## Over a long stretch every bat stays clear of the walls and moves slower
## than the bird (across: its speed; up and down: a flap).
func _check_bats(sim: GameSim, m: Hazard, what: String) -> void:
	var xs: Array[int] = m.xs.duplicate()
	var ys: Array[int] = m.ys.duplicate()
	for step in 3000:
		sim.room.step(sim)
		for i in m.count:
			assert_true(m.xs[i] - Mover.RADIUS >= 60 * SUB, "%s: clear of the left wall" % what)
			assert_true(m.xs[i] + Mover.RADIUS <= 300 * SUB, "%s: clear of the right wall" % what)
			var dx := absi(m.xs[i] - xs[i])
			var dy := absi(m.ys[i] - ys[i])
			assert_true(dx <= SimConfig.SPEED_X, "%s: a bat crosses slower than the bird" % what)
			assert_true(dy < -SimConfig.FLAP_VY, "%s: and climbs slower than a flap" % what)
			xs[i] = m.xs[i]
			ys[i] = m.ys[i]


## Every Bat Loop variant times itself off a bird holding height out of a
## portal (as test_arrival_check does for the drawn one).
func test_bats_keep_off_a_bird_out_of_a_portal() -> void:
	var index := RoomCatalog.index_of("bats")
	for v: String in ids("bats"):
		for y_px in range(120, 521, 20):
			for side in 2:
				var sim := GameSim.new(900 + y_px + side)
				sim.step(true)
				sim.state.score = 40
				sim.forced_variant = v
				sim.state.y = y_px * SUB
				sim.state.anchor_y = sim.state.y
				sim._arrive_in(side, index)
				var h: Hazard = sim.room.hazards[0]
				var clear: int = h._arrival_clear(FairLanes.arrival_path(sim))
				assert_true(
					clear >= FairLanes.ARRIVAL_PATH_MIN,
					"%s at %d px, side %d: clear %d steps" % [v, y_px, side, clear]
				)


# --- Firework Burst --------------------------------------------------------------


## A firework of `style` stepped to the start of its burst.
static func _burst(style: int, seed_value: int) -> Firework:
	var f := Firework.new(0, style)
	var sim := GameSim.new(seed_value)
	f.setup(sim, SimRng.new(seed_value))
	while f.phase != Firework.Phase.BURST:
		f.t += 1
		f.step(sim)
	return f


func test_classic_firework_is_a_ring_of_eight() -> void:
	var f := _burst(Firework.Style.RING, 3)
	assert_eq(f.spark_count(), Firework.SPARKS)
	assert_eq(f.burst_steps(), Firework.BURST)


func test_double_burst_sends_a_second_ring_into_the_gaps() -> void:
	var sim := GameSim.new(7)
	var f := _burst(Firework.Style.DOUBLE, 7)
	assert_eq(f.spark_count(), 2 * Firework.SPARKS, "two rings of sparks")
	assert_eq(f.burst_steps(), Firework.BURST + Firework.ECHO, "the burst lasts longer")
	# The second ring flies between the sparks of the first.
	for i in Firework.SPARKS:
		var a := f.spark_angle(i)
		var b := f.spark_angle(i + Firework.SPARKS)
		assert_eq(b - a, SimTrig.TURN / (2 * Firework.SPARKS), "spark %d: half a step on" % i)
	var seen_second := false
	for step in f.burst_steps():
		for i in Firework.SPARKS:
			assert_eq(f.spark_live(i), f.timer < Firework.SPARK_DEADLY, "first ring")
			var second := (
				f.timer >= Firework.ECHO and f.timer < Firework.ECHO + Firework.SPARK_DEADLY
			)
			assert_eq(f.spark_live(i + Firework.SPARKS), second, "second ring")
			if second:
				seen_second = true
				put_bird(sim, f.spark_x(i + Firework.SPARKS), f.spark_y(i + Firework.SPARKS))
				assert_true(f.kills(sim), "the second ring kills")
		f.t += 1
		f.step(sim)
	assert_true(seen_second, "the second ring came")
	assert_eq(f.phase, Firework.Phase.REST, "then it rests")


func test_cross_burst_throws_four_arms() -> void:
	var sim := GameSim.new(9)
	NoExits.clear(sim)
	var f := _burst(Firework.Style.CROSS, 9)
	assert_eq(f.spark_count(), Firework.ARMS * Firework.ARM_SPARKS)
	for step in 20:
		f.t += 1
		f.step(sim)
	for i in f.spark_count():
		var on_arm := f.spark_x(i) == f.x or f.spark_y(i) == f.y
		assert_true(on_arm, "spark %d is on an arm" % i)
		put_bird(sim, f.spark_x(i), f.spark_y(i))
		assert_true(f.kills(sim), "spark %d kills" % i)
	# Between the arms is safe.
	var d := f.spread * 7 / 10
	put_bird(sim, f.x + d, f.y + d)
	assert_false(f.kills(sim), "the diagonals are safe")


# --- Cupid Lanes -----------------------------------------------------------------


func test_double_lanes_fire_pairs_on_five_lanes() -> void:
	var sim := sim_in("cupid", "double", 5)
	var darts: Array[Hazard] = []
	darts.assign(sim.room.hazards)
	var lanes := {}
	var pairs := 0
	for step in 3000:
		sim.room.step(sim)
		for d in darts:
			if d.state != Dart.State.FLY:
				continue
			assert_ne(d.lane_y, d.lane2_y, "a pair is on two lanes")
			for y: int in d.shot_lanes():
				assert_eq((y - 110 * SUB) % (90 * SUB), 0, "on a lane")
				assert_between(y, 110 * SUB, 470 * SUB, "one of five lanes")
				lanes[y] = true
			# Halfway across, a bird on either lane is hit.
			if absi(d.x - SimConfig.WORLD_W / 2) <= d.lanes_speed / 2:
				pairs += 1
				for y: int in d.shot_lanes():
					put_bird(sim, d.x, y)
					assert_true(d.kills(sim), "both arrows kill")
	assert_eq(lanes.size(), 5, "every lane is used")
	assert_true(pairs > 10, "pairs fired: %d" % pairs)


func test_slow_volley_is_slow_with_a_long_warning() -> void:
	var sim := sim_in("cupid", "slow-volley", 2)
	var d: Hazard = sim.room.hazards[0]
	while d.state != Dart.State.GLOW:
		sim.room.step(sim)
	var warn := 0
	while d.state == Dart.State.GLOW:
		warn += 1
		sim.room.step(sim)
	assert_true(warn >= 80, "warns for %d steps (over 1.3 s)" % warn)
	var x: int = d.x
	sim.room.step(sim)
	assert_eq(absi(d.x - x), 3 * SUB, "half the classic speed")


# --- Painters --------------------------------------------------------------------


## Paints every variant's hazards for a few frames.
func test_variants_draw() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var cases := {"sawring": "", "bats": "bat", "fireworks": "", "cupid": "cupid"}
	for id: String in cases:
		for v: String in ids(id):
			var sim := sim_in(id, v, 8)
			var canvas := Canvas.new()
			canvas.sim = sim
			canvas.skin = cases[id]
			tree.root.add_child(canvas)
			for i in 200:
				sim.room.step(sim)
				if i % 25 == 0:
					canvas.queue_redraw()
					await tree.process_frame
			canvas.free()


class Canvas:
	extends Node2D
	var sim: GameSim
	var skin := ""

	func _draw() -> void:
		var look := HazardLook.new(ThemeCatalog.default_theme(), 1.0, skin)
		for h: Hazard in sim.room.hazards:
			HazardLayer.painter(h.kind).paint(self, h, look)
