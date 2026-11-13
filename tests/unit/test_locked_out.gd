extends TestCase
## Locked Out (sim/hazards/exit_key.gd): the lock, lockdown, key layouts and
## the chain.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const ExitKey := preload("res://sim/hazards/exit_key.gd")

const SUB := SimConfig.SUB
const VARIANTS: Array[String] = ["orbit", "trio", "quad", "chain"]


func test_every_variant_comes_up_with_its_key_hazard() -> void:
	var def := RoomCatalog.find("lockexit")
	assert_true(RoomInfo.ROOMS.has("lockexit"), "has room info")
	assert_eq(RoomInfo.ROOMS["lockexit"][0], "Locked Out", "its name")
	var seen := {}
	for s in 120:
		var sim := Rooms.sim_in_room("lockexit", s)
		assert_eq(sim.room.hazards.size(), 1, "one hazard")
		assert_eq(sim.room.hazards[0].kind, "exit_key", "the key hazard")
		seen[sim.room.variant_id()] = true
	assert_eq(def.variants.size(), VARIANTS.size(), "four variants")
	for v in VARIANTS:
		assert_true(seen.has(v), "variant %s comes up" % v)


func test_locked_exit_bounces_until_the_key_is_taken() -> void:
	var sim := _locked_at_exit(7)
	var k: ExitKey = sim.room.hazards[0]
	sim._check_walls()
	assert_eq(sim.state.room_index, 0, "a locked exit is a bounce")
	assert_true(sim.state.vx < 0, "turned back")
	assert_true(sim.state.alive, "and lived")
	sim = _locked_at_exit(7)
	k = sim.room.hazards[0]
	var coins := sim.state.coins
	sim.state.x = k.kx[0]
	sim.state.y = k.ky[0]
	k.touch(sim)
	assert_true(k.done(), "the key is taken")
	assert_eq(sim.state.coins - coins, ExitKey.COINS, "and pays")
	sim.state.x = SimConfig.WORLD_W - SimConfig.BIRD_RADIUS
	sim.state.y = sim.state.exit_a_y
	sim._check_walls()
	assert_eq(sim.state.room_index, 1, "the exit now leads on")


func test_locked_exit_opens_by_itself_in_the_end() -> void:
	var sim := _locked_at_exit(8)
	var k: ExitKey = sim.room.hazards[0]
	for i in ExitKey.MAX_LOCKED_BOUNCES - 1:
		k.on_bounce(sim, SimRng.new(1))
	assert_true(sim.exit_locked(), "still locked one bounce before the end")
	k.on_bounce(sim, SimRng.new(1))
	assert_false(sim.exit_locked(), "never a trap")


func test_every_variant_adds_a_spike_per_wall() -> void:
	var def := RoomCatalog.find("lockexit")
	for v in def.variants:
		assert_eq(v.extra_spikes, 1, "%s: one more spike per wall" % v.id)


func test_orbit_key_moves_and_stays_in_the_room() -> void:
	var k := _key_hazard(ExitKey.Mode.ORBIT, 9)
	var sim := _started("lockexit", 9)
	var start := Vector2i(k.kx[0], k.ky[0])
	for t in ExitKey.ORBIT_STEPS:
		k.t = t
		k.step(sim)
		assert_true(k.kx[0] >= 50 * SUB and k.kx[0] <= 310 * SUB, "clear of the walls")
		assert_true(k.ky[0] >= 160 * SUB and k.ky[0] <= 500 * SUB, "clear of the edges")
	k.t = 100
	k.step(sim)
	assert_ne(Vector2i(k.kx[0], k.ky[0]), start, "it moves")


func test_key_layouts_follow_the_rules_on_every_seed() -> void:
	for mode: int in [ExitKey.Mode.TRIO, ExitKey.Mode.QUAD]:
		for s in 300:
			var k := _key_hazard(mode, s)
			var band := ExitKey.LAYOUT_SPAN / k.count
			for i in k.count:
				var top := (ExitKey.LAYOUT_TOP + i * band) * SUB
				assert_true(k.ky[i] >= top and k.ky[i] <= top + band * SUB, "one key per band")
				assert_true(k.kx[i] >= 56 * SUB and k.kx[i] <= 304 * SUB, "clear of the walls")
				for j in range(i + 1, k.count):
					var dx := k.kx[i] - k.kx[j]
					var dy := k.ky[i] - k.ky[j]
					assert_true(
						dx * dx + dy * dy >= ExitKey.KEYS_APART * ExitKey.KEYS_APART,
						"keys apart (mode %d seed %d)" % [mode, s]
					)


func test_every_key_is_needed_and_the_last_pays_a_bonus() -> void:
	var sim := _locked_at_exit(3, ExitKey.Mode.QUAD)
	var k: ExitKey = sim.room.hazards[0]
	var coins := sim.state.coins
	for i in 3:
		sim.state.x = k.kx[i]
		sim.state.y = k.ky[i]
		k.touch(sim)
	assert_eq(k.got, 3, "three of four")
	assert_true(sim.exit_locked(), "still locked")
	assert_eq(sim.state.coins - coins, 3, "a coin each")
	sim.state.x = k.kx[3]
	sim.state.y = k.ky[3]
	k.touch(sim)
	assert_false(sim.exit_locked(), "open with every key")
	assert_eq(sim.state.coins - coins, 4 + 4, "the last pays one plus a bonus per key")


func test_chain_shows_one_key_at_a_time_behind_the_bird() -> void:
	var sim := _locked_at_exit(5, ExitKey.Mode.CHAIN)
	var k: ExitKey = sim.room.hazards[0]
	assert_true(k.shown(0) and not k.shown(1), "only the first")
	sim.state.x = k.kx[0]
	sim.state.y = k.ky[0]
	sim.state.vx = SimConfig.SPEED_X
	k.touch(sim)
	assert_true(k.shown(1) and not k.shown(0), "the next one shows up")
	assert_true(k.kx[1] <= ExitKey.CHAIN_OFF_MAX, "by the wall behind the bird")
	var far := absi(k.ky[1] - sim.state.y)
	var clamped := k.ky[1] == ExitKey.KEY_MIN_Y or k.ky[1] == ExitKey.KEY_MAX_Y
	assert_true(far >= ExitKey.CHAIN_D_MIN or clamped, "far from the bird's height")


func test_lockdown_grows_the_wall_but_keeps_the_free_run() -> void:
	var sim := _locked_at_exit(4)
	var k: ExitKey = sim.room.hazards[0]
	# The wall without the key, so no bounce spot is cleared.
	var far := 1 if k.kx[0] < SimConfig.WORLD_W / 2 else 0
	var gap := sim.room.def.gap
	for s in 40:
		var mask := RoomRules.generate_wall(SimRng.new(s), 40, sim.room.def)
		for b in ExitKey.MAX_LOCKED_BOUNCES:
			k.locked_bounces = b
			var out := k.adjust_wall(sim, far, mask)
			var added := _bits(out) - _bits(mask)
			var room_left := SimConfig.SLOT_COUNT - _bits(mask) - RoomRules.longest_gap(mask)
			assert_eq(
				added, mini(mini(ExitKey.LOCKDOWN_MAX, b + 1), room_left), "one more per bounce"
			)
			assert_true((out & mask) == mask, "only adds")
			assert_true(RoomRules.longest_gap(out) >= gap, "the free run stays")
	k.locked_bounces = ExitKey.MAX_LOCKED_BOUNCES
	var plain := RoomRules.generate_wall(SimRng.new(1), 40, sim.room.def)
	assert_eq(k.adjust_wall(sim, far, plain), plain, "nothing once the lock gave up")


func test_a_wall_band_key_keeps_a_bounce_spot_and_pulls_the_exit_near() -> void:
	var sim := _started("lockexit", 6)
	var k := _key_hazard(ExitKey.Mode.CHAIN, 6)
	sim.room.hazards[0] = k
	var side := 0 if k.kx[0] < SimConfig.WORLD_W / 2 else 1
	var full := (1 << SimConfig.SLOT_COUNT) - 1
	var first := k.adjust_wall(sim, side, full)
	var second := k.adjust_wall(sim, side, full)
	assert_eq(first, full, "not on the first wall")
	assert_ne(second, full, "a spot on the second")
	for slot in SimConfig.SLOT_COUNT:
		if (second >> slot) & 1 == 0:
			assert_true(
				absi(SimConfig.slot_center_y(slot) - k.ky[0]) <= ExitKey.SPOT_HALF, "at the key"
			)
	assert_true(k.blocks_exit(sim, side, k.ky[0] + ExitKey.EXIT_NEAR + SUB), "no exit far away")
	assert_false(k.blocks_exit(sim, side, k.ky[0]), "an exit near the key is fine")
	assert_false(k.blocks_exit(sim, 1 - side, k.ky[0] + 300 * SUB), "the other wall is free")


static func _key_hazard(mode: int, seed_value: int) -> ExitKey:
	var sim := _started("lockexit", seed_value)
	var k := ExitKey.new(mode)
	k.setup(sim, SimRng.new(seed_value))
	return k


static func _bits(mask: int) -> int:
	var n := 0
	for slot in SimConfig.SLOT_COUNT:
		n += (mask >> slot) & 1
	return n


static func _started(id: String, seed_value: int) -> GameSim:
	var sim := Rooms.sim_in_room(id, seed_value)
	sim.state.started = true
	return sim


## A Locked Out room with its exit open on the right, the bird at it, its key
## hazard in mode `mode`.
static func _locked_at_exit(seed_value: int, mode: int = ExitKey.Mode.ORBIT) -> GameSim:
	var sim := _started("lockexit", seed_value)
	var k := ExitKey.new(mode)
	k.setup(sim, SimRng.new(seed_value))
	sim.room.hazards[0] = k
	sim.state.exit_open = true
	sim.state.exit_side = 1
	sim.state.exit_a_y = SimConfig.slot_center_y(6)
	sim.state.exit_a_kind = SimState.ExitKind.NORMAL
	sim.state.vx = SimConfig.SPEED_X
	sim.state.x = SimConfig.WORLD_W - SimConfig.BIRD_RADIUS
	sim.state.y = sim.state.exit_a_y
	return sim
