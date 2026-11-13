extends TestCase
## Spike Rain's variants: Classic, Drizzle, Hail, Sweep, Shatter, Wobble and
## Stake. Each is fair (a long enough look before a drop reaches the bird) and
## does what its name says.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const Drop := preload("res://sim/hazards/drop.gd")

const SUB := SimConfig.SUB
const IDS := ["classic", "drizzle", "hail", "sweep", "shatter", "wobble", "stake"]
## The middle of the room, where the bird usually flies.
const MID := 320 * SUB


## A Spike Rain room playing the variant `id`.
static func rain(id: String) -> GameSim:
	for s in 400:
		var sim := Rooms.sim_in_room("rain", s)
		if sim.room.variant_id() == id:
			sim.state.started = true
			return sim
	return null


static func drops(sim: GameSim) -> Array[Drop]:
	var out: Array[Drop] = []
	for h in sim.room.hazards:
		out.append(h as Drop)
	return out


func test_the_variants() -> void:
	var ids: Array[String] = []
	for v in RoomCatalog.find("rain").variants:
		ids.append(v.id)
	assert_eq(ids, IDS)
	for id: String in IDS:
		assert_true(rain(id) != null, "%s shows up" % id)


func test_classic_plays_as_before() -> void:
	var list := drops(rain("classic"))
	assert_eq(list.size(), 2)
	for d in list:
		assert_eq(d.style, Drop.Style.PLAIN)
		assert_eq(d.warn, 45)
		assert_eq(d.radius, 10 * SUB)
		assert_eq(d.speed, 10 * SUB)
		assert_eq(d.gap, 25)
		assert_eq(d.column, -1)
	assert_eq([list[0].delay, list[1].delay], [30, 70])


## Every drop is marked for at least 0.75 s, takes at least 1.2 s from its
## mark to the middle of the room, and the first mark waits as long as
## today's, so a bird out of a portal is never in the way.
func test_every_variant_is_fair() -> void:
	for id: String in IDS:
		for d in drops(rain(id)):
			assert_true(d.warn >= Drop.WARN, "%s: marked long enough" % id)
			var to_mid := d.warn + (MID - SimConfig.KILL_TOP) / d.speed
			assert_true(to_mid >= 72, "%s: %d steps from mark to mid-room" % [id, to_mid])
			assert_true(d.delay >= 30, "%s: the first mark waits" % id)
			assert_true(d.radius <= Drop.RADIUS + 3 * SUB, "%s: drop size" % id)


func test_drizzle_is_the_gentle_one() -> void:
	var classic := drops(rain("classic"))[0]
	for d in drops(rain("drizzle")):
		assert_true(d.speed < classic.speed, "falls slower")
		assert_true(d.warn > classic.warn, "is marked longer")
		assert_true(d.warn >= 75, "about 1.25 s")


func test_hail_has_four_small_drops() -> void:
	var list := drops(rain("hail"))
	assert_eq(list.size(), 4)
	for d in list:
		assert_true(d.radius < Drop.RADIUS, "smaller")
		# Four at once leave no room to react late: each is marked a second.
		assert_true(d.warn >= SimConfig.ARRIVAL_BLIND, "marked a full second")


## Four fixed columns fall left to right, then right to left, and back.
func test_sweep_goes_one_way_then_back() -> void:
	var sim := rain("sweep")
	var list := drops(sim)
	assert_eq(list.size(), 4)
	var passes: Array = []
	var marks: Array[int] = []
	for i in 700:
		sim.room.step(sim)
		for d in list:
			if d.warning() and d.timer == d.warn:
				marks.append(d.x)
				if marks.size() == 4:
					passes.append(marks.duplicate())
					marks.clear()
	assert_true(passes.size() >= 3, "several passes (%d)" % passes.size())
	var right: Array = [45 * SUB, 135 * SUB, 225 * SUB, 315 * SUB]
	var left := right.duplicate()
	left.reverse()
	assert_eq(passes[0], right, "first pass left to right")
	assert_eq(passes[1], left, "then back")
	assert_eq(passes[2], right, "and again")


## The shards come out where the drop hit the floor and skip along it: a low
## bird beside the column is hit, a bird higher up is not.
func test_shatter_shards_skip_along_the_floor() -> void:
	var sim := rain("shatter")
	var d := drops(sim)[0]
	var shards := 0
	var low_hit := false
	for i in 900:
		sim.room.step(sim)
		if d.shard_t <= 0:
			continue
		shards += 1
		assert_true(d.shard_y >= SimConfig.KILL_BOTTOM - 40 * SUB, "shards stay low")
		assert_true(d.shard_y <= Drop.SHARD_FLOOR, "and above the floor line")
		sim.state.x = d.shard_x + d.shard_dx
		sim.state.y = d.shard_y
		low_hit = low_hit or d.kills(sim)
		sim.state.y = d.shard_y - Drop.SHARD_RADIUS - SimConfig.BIRD_RADIUS - SUB
		assert_false(d.kills(sim), "a bird just above a shard is safe")
		if d.shard_t == 1:
			assert_true(d.shard_dx <= 135 * SUB, "they reach about 130 px")
	assert_true(shards > 0, "the drop shattered")
	assert_true(low_hit, "a shard kills a low bird")


## A wobbling drop sways around its marked column, never past the band, and
## its column keeps the whole band inside the usual range.
func test_wobble_sways_inside_its_band() -> void:
	var sim := rain("wobble")
	var d := drops(sim)[0]
	var left := 0
	var right := 0
	for i in 900:
		sim.room.step(sim)
		if not d.falling():
			continue
		var off := d.x - d.base_x
		assert_true(absi(off) <= Drop.SWAY, "sway within %d px" % (Drop.SWAY / SUB))
		assert_true(d.base_x - Drop.SWAY >= Drop.MIN_X, "band starts inside the range")
		assert_true(d.base_x + Drop.SWAY <= Drop.MAX_X, "and ends inside it")
		if off < -Drop.SWAY / 2:
			left += 1
		if off > Drop.SWAY / 2:
			right += 1
	assert_true(left > 0 and right > 0, "it sways both ways")


## A stake lands on a floor spike's tip (never the two at the walls) and that
## spike grows: a low bird above it dies, one beside it or after it shrank
## lives.
func test_stake_grows_the_floor_spike_it_lands_on() -> void:
	var sim := rain("stake")
	var d := drops(sim)[0]
	var grown := false
	var shrank := false
	for i in 900:
		sim.room.step(sim)
		if d.warning():
			var slot := (d.base_x - Drop.FLOOR_SPIKE_W / 2) / Drop.FLOOR_SPIKE_W
			assert_eq(d.base_x % Drop.FLOOR_SPIKE_W, Drop.FLOOR_SPIKE_W / 2, "on a spike tip")
			assert_true(slot >= 1 and slot <= Drop.FLOOR_SPIKES - 2, "not at a wall")
		if not d.staked():
			continue
		assert_false(d.falling(), "the drop is gone")
		# A bird 20 px above the floor line, right over the spike.
		sim.state.x = d.base_x
		sim.state.y = SimConfig.KILL_BOTTOM - SimConfig.BIRD_RADIUS - 20 * SUB
		if d.stake_height() == Drop.STAKE_HEIGHT:
			grown = true
			assert_true(d.kills(sim), "the grown spike kills a low bird above it")
			sim.state.x = d.base_x + 60 * SUB
			assert_false(d.kills(sim), "but not one beside it")
			sim.state.x = d.base_x
			sim.state.y = SimConfig.KILL_BOTTOM - Drop.STAKE_HEIGHT - SimConfig.BIRD_RADIUS
			sim.state.y -= 3 * SUB
			assert_false(d.kills(sim), "nor one just over its tip")
		if d.timer == 1:
			shrank = true
			assert_false(d.kills(sim), "nearly gone again")
	assert_true(grown and shrank, "the spike grew and shrank")


func test_variants_replay_the_same() -> void:
	for id: String in IDS:
		var a := rain(id)
		var b := rain(id)
		for i in 600:
			a.room.step(a)
			b.room.step(b)
		var ha := 0
		var hb := 0
		for h in a.room.hazards:
			ha = h.checksum(ha)
		for h in b.room.hazards:
			hb = h.checksum(hb)
		assert_eq(ha, hb, "%s is deterministic" % id)


## Every variant draws through a few hundred frames without errors.
func test_every_variant_draws() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var canvas := RainCanvas.new()
	tree.root.add_child(canvas)
	for id: String in IDS:
		var sim := rain(id)
		canvas.hazards = sim.room.hazards
		for ink in [false, true]:
			canvas.ink = ink
			for i in 300:
				sim.room.step(sim)
				if i % 15 == 0:
					canvas.queue_redraw()
					await tree.process_frame
	canvas.free()


class RainCanvas:
	extends Node2D
	var hazards: Array[Hazard] = []
	var ink := false

	func _draw() -> void:
		var theme := ThemeCatalog.default_theme()
		if ink:
			theme = HazardLayer.ink_theme(theme)
		for h in hazards:
			HazardLayer.painter(h.kind).paint(self, h, HazardLook.new(theme, 1.0, "", ink))
