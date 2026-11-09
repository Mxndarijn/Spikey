extends TestCase
## Coins: a wall bounce places one at a random spot when none is out; flying
## into it collects it. Part of the gameplay rules (GAMEPLAY_VERSION 2).

const HUD_SCENE := preload("res://game/ui/hud.tscn")
const Rooms := preload("res://tests/unit/test_rooms.gd")


## Flies with the gap-seeking test bot until the next wall bounce.
static func _step_until_bounce(sim: GameSim) -> bool:
	var bot := SimRng.new(1)
	var limit := sim.state.tick + 2000
	while sim.state.alive and sim.state.tick < limit:
		sim.step(SimBots.gap_seeker(sim, bot))
		if GameSim.Event.BOUNCE in sim.events:
			return true
	return false


func test_no_coin_until_the_first_bounce() -> void:
	var sim := GameSim.new(5)
	sim.step(true)
	assert_false(sim.state.coin_active)
	assert_true(_step_until_bounce(sim), "bird reaches a wall")
	assert_true(sim.state.coin_active, "a bounce places a coin")
	assert_true(GameSim.Event.COIN_SPAWN in sim.events, "and says so")
	assert_between(sim.state.coin_x, SimConfig.COIN_MIN_X, SimConfig.COIN_MAX_X)
	assert_between(sim.state.coin_y, SimConfig.COIN_MIN_Y, SimConfig.COIN_MAX_Y)


func test_only_one_coin_at_a_time() -> void:
	var sim := GameSim.new(9)
	sim.step(true)
	_step_until_bounce(sim)
	var x := sim.state.coin_x
	var y := sim.state.coin_y
	# Move the coin out of the bird's way so it can't be collected, then bounce again.
	sim.state.coin_y = SimConfig.COIN_MAX_Y
	y = sim.state.coin_y
	assert_true(_step_until_bounce(sim), "second bounce")
	assert_true(sim.state.coin_active)
	assert_eq(sim.state.coin_x, x, "the same coin stays")
	assert_eq(sim.state.coin_y, y, "no second coin")
	assert_false(GameSim.Event.COIN_SPAWN in sim.events)


func test_flying_into_the_coin_collects_it() -> void:
	var sim := GameSim.new(3)
	sim.step(true)
	sim.state.coin_active = true
	sim.state.coin_x = sim.state.x + sim.state.vx
	sim.state.coin_y = sim.state.y
	sim.step(false)
	assert_false(sim.state.coin_active, "coin is gone")
	assert_eq(sim.state.coins, 1)
	assert_true(GameSim.Event.COIN in sim.events)


func test_coins_never_sit_in_a_deadly_spot() -> void:
	var r := SimConfig.COIN_RADIUS
	assert_true(SimConfig.COIN_MIN_X - r > SimConfig.SPIKE_DEPTH, "clear of left spikes")
	assert_true(
		SimConfig.COIN_MAX_X + r < SimConfig.WORLD_W - SimConfig.SPIKE_DEPTH,
		"clear of right spikes"
	)
	var reach := SimConfig.BIRD_RADIUS * 2
	assert_true(SimConfig.COIN_MIN_Y - r > SimConfig.KILL_TOP + reach, "clear of the ceiling")
	assert_true(SimConfig.COIN_MAX_Y + r < SimConfig.KILL_BOTTOM - reach, "clear of the floor")


func test_a_good_player_collects_coins() -> void:
	var seeds := SimRng.new(77)
	var total := 0
	for i in 10:
		total += SimBots.play(seeds.next_u32(), SimBots.gap_seeker, i + 1, 3000).coins
	assert_true(total > 0, "coins are reachable (bot collected %d)" % total)


func test_replay_checks_coins() -> void:
	var replay := SimBots.play(4242, SimBots.gap_seeker, 2, 3000)
	assert_true(replay.verify().ok, "honest run verifies")
	replay.coins += 3
	var result := replay.verify()
	assert_false(result.ok, "extra coins are rejected")
	assert_true(result.reason.begins_with("coins mismatch"), result.reason)


func test_collected_coin_flies_to_the_counter() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	hud.set_run_coins(2)
	hud.fly_coin(Vector2(180, 400), 3)
	assert_eq(hud.flying_coins(), 1, "a coin is on its way")
	assert_eq(hud.run_coins_text(), "2", "counter waits for the coin to land")
	await tree.create_timer(Hud.FLY_TIME + 0.2).timeout
	assert_eq(hud.flying_coins(), 0, "the coin landed")
	assert_eq(hud.run_coins_text(), "3", "counter goes up when it lands")
	hud.free()


func test_hud_counts_run_coins() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.set_run_coins(4)
	assert_eq(hud.run_coins_text(), "4")
	hud.free()


func test_practice_runs_place_no_bounce_coins() -> void:
	var sim := GameSim.new(5, Seasons.NONE, RoomCatalog.index_of("open"))
	assert_true(sim.is_practice())
	sim.step(true)
	for i in 3:
		assert_true(_step_until_bounce(sim), "bounce %d" % i)
		assert_false(sim.state.coin_active, "no coin after a practice bounce")
	var real := GameSim.new(5)
	real.step(true)
	assert_true(_step_until_bounce(real))
	assert_true(real.state.coin_active, "real runs still place one")


func test_coin_garden_bounces_add_a_coin_even_with_one_out() -> void:
	var sim := Rooms.sim_in_room("garden", 6)
	sim.step(true)
	assert_true(_step_until_bounce(sim), "first bounce")
	assert_true(sim.state.coin_active, "the usual bounce coin")
	# Keep the coin out of the bird's way so it stays out.
	sim.state.coin_y = SimConfig.COIN_MAX_Y
	var before := _room_coins(sim)
	assert_true(_step_until_bounce(sim), "second bounce")
	assert_true(sim.state.coin_active, "the bounce coin is still out")
	assert_eq(_room_coins(sim), before + 1, "and another coin joined it")


func test_other_rooms_keep_one_bounce_coin() -> void:
	var sim := Rooms.sim_in_room("open", 6)
	sim.step(true)
	assert_true(_step_until_bounce(sim))
	sim.state.coin_y = SimConfig.COIN_MAX_Y
	var before := _room_coins(sim)
	assert_true(_step_until_bounce(sim))
	assert_eq(_room_coins(sim), before, "no extra coin outside Coin Garden")


## Coins the room has placed so far (collected ones included).
static func _room_coins(sim: GameSim) -> int:
	var n := 0
	for h in sim.room.hazards:
		if h.kind == "coin":
			n += 1
	return n
