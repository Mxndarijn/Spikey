extends TestCase
## Sky and bonus rooms (Bubble Lift, Spike Rain, Orchard Drop, Keepy-Uppy)
## and the seasonal path mover and firework hazards. Updraft: test_updraft.gd.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const Mover := preload("res://sim/hazards/mover.gd")
const Firework := preload("res://sim/hazards/firework.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")

const SUB := SimConfig.SUB
const SKY_ROOMS := {
	"bubbles": ["bubble", "bubble", "bubble"],
	"rain": ["drop", "drop"],
	"orchard": ["orchard_spawner", "drop"],
	"keepy": ["keepy_ball"],
}


func test_sky_rooms_spawn_their_hazards() -> void:
	for id: String in SKY_ROOMS:
		var sim := Rooms.sim_in_room(id, 3)
		var kinds: Array[String] = []
		for h in sim.room.hazards:
			kinds.append(h.kind)
		if id == "bubbles":
			# Spiky Bubbles has four (test_coin_variants.gd).
			assert_true(kinds.size() == 3 or kinds.size() == 4, "bubbles has 3 or 4")
			kinds.resize(3)
		if id == "rain":
			# Spike Rain's variants have two or four drops (test_rain_variants.gd).
			assert_true(kinds.size() == 2 or kinds.size() == 4, "rain has 2 or 4 drops")
			kinds.resize(2)
		assert_eq(kinds, SKY_ROOMS[id], "%s builds its hazards" % id)
	assert_eq(RoomCatalog.find("orchard").group, "bonus")
	assert_true(RoomCatalog.find("orchard").max_spikes <= 2, "orchard is a breather")


## A new room starts with the bird at a side wall: nothing there may kill it.
func test_nothing_spawns_on_the_bird_at_a_wall() -> void:
	for id: String in SKY_ROOMS:
		for s in 20:
			for wall_x in [24 * SUB, SimConfig.WORLD_W - 24 * SUB]:
				for y_px in range(80, 580, 40):
					var sim := Rooms.sim_in_room(id, s)
					sim.state.x = wall_x
					sim.state.y = y_px * SUB
					for h in sim.room.hazards:
						assert_false(h.kills(sim), "%s seed %d clear of the wall" % [id, s])


func test_bubble_carries_the_bird_and_a_tap_releases_it() -> void:
	var sim := _started("bubbles", 2)
	var b: Hazard = sim.room.hazards[0]
	b.y = 450 * SUB
	sim.state.x = b.x
	sim.state.y = b.y
	sim.state.vx = 0
	sim.state.vy = 0
	sim.step(false)
	assert_true(b.carrying, "caught by the bubble")
	var y0 := sim.state.y
	for i in 20:
		sim.step(false)
		assert_eq(sim.state.y, b.y, "rides with the bubble")
	assert_eq(y0 - sim.state.y, -20 * b.vy, "rises at the bubble's speed, no gravity")
	sim.step(true)
	assert_false(b.carrying, "a tap pops it")
	assert_true(b.y > SimConfig.KILL_BOTTOM, "popped bubble goes back below the floor")
	assert_true(sim.state.alive)
	for h in sim.room.hazards:
		assert_false(h.kills(sim), "bubbles are safe")


func test_bubble_pops_below_the_ceiling() -> void:
	var sim := _started("bubbles", 4)
	var b: Hazard = sim.room.hazards[0]
	b.y = 160 * SUB
	sim.state.x = b.x
	sim.state.y = b.y
	sim.state.vx = 0
	sim.state.vy = 0
	sim.step(false)
	assert_true(b.carrying)
	var popped := false
	for i in 120:
		sim.step(false)
		if not b.carrying:
			popped = true
			break
	assert_true(popped, "pops at the top")
	assert_true(sim.state.alive, "the bird is let go before the ceiling")
	assert_true(sim.state.y - SimConfig.BIRD_RADIUS > SimConfig.KILL_TOP + 4 * SUB)


func test_drop_warns_then_falls_and_only_the_falling_drop_kills() -> void:
	var sim := GameSim.new(5)
	var d := Drop.new(10)
	d.setup(sim, SimRng.new(5))
	var warn_steps := 0
	var warn_x := -1
	var falls := 0
	for i in 600:
		d.t += 1
		d.step(sim)
		if d.warning():
			if warn_steps == 0:
				warn_x = d.x
			warn_steps += 1
			sim.state.x = d.x
			sim.state.y = SimConfig.KILL_TOP + 30 * SUB
			assert_false(d.kills(sim), "the warning is safe")
		elif d.falling():
			if warn_steps > 0:
				assert_true(warn_steps >= Drop.WARN - 1, "warned long enough before falling")
				assert_eq(d.x, warn_x, "falls down the marked column")
				falls += 1
			warn_steps = 0
			sim.state.x = d.x
			sim.state.y = d.y
			assert_true(d.kills(sim), "the falling drop kills")
			sim.state.x = d.x + 40 * SUB
			assert_false(d.kills(sim), "only its own column")
		else:
			sim.state.x = d.x
			sim.state.y = 300 * SUB
			assert_false(d.kills(sim), "nothing while waiting")
	assert_true(falls >= 4, "drops keep coming (%d)" % falls)


func test_rain_room_kills_with_a_drop() -> void:
	var sim := _started("rain", 6)
	var d: Hazard = sim.room.hazards[0]
	while not d.falling():
		sim.room.step(sim)
	sim.room.step(sim)
	sim.state.x = d.x
	sim.state.y = d.y + d.speed
	sim.state.vx = 0
	sim.state.vy = 0
	sim.step(false)
	assert_false(sim.state.alive, "hit by the drop")
	assert_eq(sim.state.death_cause, SimState.DeathCause.HAZARD)


func test_orchard_drops_coins_and_pinecones() -> void:
	var sim := _started("orchard", 7)
	var spawner: Hazard = sim.room.hazards[0]
	var cone: Hazard = sim.room.hazards[1]
	assert_eq(cone.kind, "drop")
	assert_eq(RoomSkins.of("orchard"), "pinecone", "its drops draw as pinecones")
	for i in 120:
		sim.room.step(sim)
	assert_true(spawner.live_count() >= 3, "coins are falling")
	var i0: int = spawner.live.find(true)
	sim.state.x = spawner.xs[i0]
	sim.state.y = spawner.ys[i0]
	assert_false(spawner.kills(sim), "coins are safe")
	spawner.touch(sim)
	assert_eq(sim.state.coins, 1, "a falling coin is collected")
	assert_false(spawner.live[i0])
	var fell := false
	for i in 400:
		sim.room.step(sim)
		fell = fell or cone.falling()
	assert_true(fell, "a pinecone falls now and then")


func test_keepy_ball_pays_a_coin_per_bump_and_dies_on_the_floor() -> void:
	var sim := _classic_keepy(8)
	var ball: Hazard = sim.room.hazards[0]
	ball.x = 180 * SUB
	ball.y = 300 * SUB
	ball.vy = 3 * SUB
	sim.state.x = ball.x + 10 * SUB
	sim.state.y = ball.y + 30 * SUB
	assert_false(ball.kills(sim), "the ball is safe")
	ball.touch(sim)
	assert_eq(sim.state.coins, 1, "one coin per bump")
	assert_true(ball.vy < 0, "kicked up")
	assert_true(ball.vx < 0, "pushed away from the side it was hit on")
	sim.state.y = ball.y + 30 * SUB
	ball.touch(sim)
	assert_eq(sim.state.coins, 1, "the same bump pays once")
	for i in KeepyBall.COOLDOWN:
		ball.step(sim)
	sim.state.x = ball.x
	sim.state.y = ball.y + 30 * SUB
	ball.touch(sim)
	assert_eq(sim.state.coins, 2, "a second bump pays again")
	ball.vy = KeepyBall.MAX_VY
	ball.y = SimConfig.KILL_BOTTOM - KeepyBall.RADIUS - 2 * SUB
	sim.room.step(sim)
	assert_false(ball.alive, "gone once it reaches the floor")


func test_keepy_ball_drops_in_from_above() -> void:
	var sim := _classic_keepy(9)
	var ball: Hazard = sim.room.hazards[0]
	assert_true(ball.y < SimConfig.KILL_TOP, "starts above the ceiling")
	for i in 60:
		sim.room.step(sim)
	assert_true(ball.y > SimConfig.KILL_TOP + KeepyBall.RADIUS, "falls into the room")


func test_mover_paths_are_deterministic_and_deadly() -> void:
	for mode in ["figure8", "wave"]:
		var a := _run_mover(mode, 11)
		var b := _run_mover(mode, 11)
		assert_eq(a.checksum(1), b.checksum(1), "%s replays the same" % mode)
		assert_ne(a.checksum(1), _run_mover(mode, 12).checksum(1), "%s phase from the rng" % mode)
		var sim := GameSim.new(1)
		sim.state.x = a.xs[0]
		sim.state.y = a.ys[0]
		assert_true(a.kills(sim), "%s creature kills" % mode)
		sim.state.x = 20 * SUB
		assert_false(a.kills(sim), "%s clear of the wall" % mode)


func test_mover_stays_clear_of_the_walls() -> void:
	for mode in ["figure8", "wave"]:
		var m := Mover.new(mode, 3)
		var sim := GameSim.new(2)
		m.setup(sim, SimRng.new(2))
		var turned := false
		for i in 900:
			m.t += 1
			m.step(sim)
			for k in m.count:
				assert_between(m.xs[k], 60 * SUB, 300 * SUB, "%s x in the middle" % mode)
				assert_between(m.ys[k], 100 * SUB, 540 * SUB, "%s y in the room" % mode)
			turned = turned or m.facing[0] < 0
		assert_true(turned, "%s turns back" % mode)


func test_firework_warns_on_the_pad_then_rocket_and_sparks_kill() -> void:
	var sim := GameSim.new(3)
	var f := Firework.new(0)
	f.setup(sim, SimRng.new(3))
	var pad := 0
	var launches := 0
	var spark_kill := false
	var faded_safe := false
	for i in 1200:
		f.t += 1
		f.step(sim)
		match f.phase:
			Firework.Phase.PAD:
				pad += 1
				sim.state.x = f.x
				sim.state.y = f.y
				assert_false(f.kills(sim), "the rocket on the pad is a warning")
			Firework.Phase.CLIMB:
				if pad > 0:
					assert_true(pad >= Firework.PAD - 1, "sat on the pad long enough")
					launches += 1
				pad = 0
				sim.state.x = f.x
				sim.state.y = f.y
				assert_true(f.kills(sim), "the climbing rocket kills")
			Firework.Phase.BURST:
				assert_eq(f.y, f.burst_y, "bursts at its height")
				sim.state.x = f.spark_x(2)
				sim.state.y = f.spark_y(2)
				if f.timer < Firework.SPARK_DEADLY:
					spark_kill = spark_kill or f.kills(sim)
				else:
					faded_safe = faded_safe or not f.kills(sim)
	assert_true(launches >= 4, "keeps launching (%d)" % launches)
	assert_true(spark_kill, "bright sparks kill")
	assert_true(faded_safe, "faded sparks are safe")


func test_firework_is_deterministic() -> void:
	var a := _run_firework(21)
	var b := _run_firework(21)
	assert_eq(a.checksum(1), b.checksum(1), "same seed, same show")
	assert_ne(a.checksum(1), _run_firework(22).checksum(1), "column from the rng")


func test_new_hazards_have_painters() -> void:
	for kind in ["updraft", "bubble", "drop", "keepy_ball", "orchard_spawner", "mover", "firework"]:
		assert_true(ResourceLoader.exists(HazardLayer.painter_path(kind)), "%s painter" % kind)


## Draws the movers and fireworks (not in a room of this batch) for a few
## frames with every skin.
func test_mover_and_firework_draw() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var sim := GameSim.new(3)
	var canvas := SkinCanvas.new()
	tree.root.add_child(canvas)
	for skin in ["bat", "bee", ""]:
		canvas.add(Mover.new("figure8" if skin == "bat" else "wave", 3), skin)
	for skin in ["icicle", "pinecone", ""]:
		canvas.add(Drop.new(0), skin)
	canvas.add(Firework.new(0), "")
	canvas.add(KeepyBall.new(), "beachball")
	var list: Array[Hazard] = []
	for pair in canvas.items:
		list.append(pair[0])
	sim.room.hazards = list
	for h in list:
		h.setup(sim, SimRng.new(4))
	for i in 140:
		sim.room.step(sim)
		if i % 20 == 0:
			canvas.queue_redraw()
			await tree.process_frame
	canvas.free()


## Paints hazards each with its own skin (a room has one skin for all of them).
class SkinCanvas:
	extends Node2D
	## [hazard, skin] pairs.
	var items: Array[Array] = []

	func add(h: Hazard, skin: String) -> void:
		items.append([h, skin])

	func _draw() -> void:
		for pair in items:
			var h: Hazard = pair[0]
			var look := HazardLook.new(ThemeCatalog.default_theme(), 1.0, str(pair[1]))
			HazardLayer.painter(h.kind).paint(self, h, look)


static func _started(id: String, seed_value: int) -> GameSim:
	var sim := Rooms.sim_in_room(id, seed_value)
	sim.state.started = true
	return sim


## Keepy-Uppy with its one classic ball.
static func _classic_keepy(seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value, Seasons.NONE, RoomCatalog.index_of("keepy"), "classic")
	sim.state.started = true
	return sim


static func _run_mover(mode: String, seed_value: int) -> Hazard:
	var m := Mover.new(mode, 3)
	var sim := GameSim.new(seed_value)
	m.setup(sim, SimRng.new(seed_value))
	for i in 600:
		m.t += 1
		m.step(sim)
	return m


static func _run_firework(seed_value: int) -> Hazard:
	var f := Firework.new(0)
	var sim := GameSim.new(seed_value)
	f.setup(sim, SimRng.new(seed_value))
	for i in 700:
		f.t += 1
		f.step(sim)
	return f
