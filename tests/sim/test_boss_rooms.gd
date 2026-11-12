extends TestCase
## Boss rooms: the exit at every SimConfig.BOSS_EVERY points leads into one;
## its exit opens after BOSS_POINTS bounces, is the fork, and pays the boss's
## coins; its boss changes phase on the bounces and breaks when the exit opens.
## (A bot playing through every boss is FastSim's `passable` check.)

const Boss := preload("res://sim/hazards/boss.gd")


func _boss_index(id: String) -> int:
	return RoomCatalog.index_of(id)


## A real run put just before the boss portal: score BOSS_EVERY, the exit open
## on the wall ahead, then flown through.
func _into_boss(seed_value: int = 77) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.state.started = true
	sim.state.score = SimConfig.BOSS_EVERY
	sim._go_through(1, SimState.ExitKind.NORMAL, 320 * SimConfig.SUB)
	return sim


## Bounces the bird off a wall as GameSim does, without flying across.
func _bounce(sim: GameSim) -> void:
	var side := 0 if sim.state.vx > 0 else 1
	sim.state.vx = -sim.state.vx
	sim._bounce_score()
	sim._new_wall(side)
	sim._maybe_open_exit()


func test_the_usual_picker_never_picks_a_boss() -> void:
	var rng := SimRng.new(5)
	for i in 3000:
		var next := RoomCatalog.pick_next(rng, -1, 400, Seasons.NONE)
		assert_false(RoomCatalog.all()[next].boss)


func test_three_bosses_in_the_catalog() -> void:
	assert_eq(RoomCatalog.bosses().size(), 3)
	for id: String in ["boss_watcher", "boss_crusher", "boss_saw"]:
		var def := RoomCatalog.find(id)
		assert_true(def != null and def.boss, id)


func test_the_exit_at_every_boss_score_leads_into_a_boss() -> void:
	var sim := _into_boss()
	assert_true(sim.room.def.boss, "a boss room")
	assert_eq(sim.room.entry_score, SimConfig.BOSS_EVERY)
	assert_eq(sim.next_exit_score(), SimConfig.BOSS_EVERY + SimConfig.BOSS_POINTS)
	assert_true(sim.state.arrival_hold >= SimConfig.BOSS_HOLD, "the bird waits while it comes in")
	assert_eq(sim.state.bosses_met, RoomCatalog.boss_bit(sim.room.index))
	assert_true(ExitPlanner.is_fork(sim, sim.next_exit_score()), "the boss's exit is the fork")
	assert_false(sim._boss_due(), "out of a boss room the next portal is not a boss")


func test_no_fork_at_a_boss_score_and_forks_elsewhere_stay() -> void:
	var sim := GameSim.new(9)
	assert_false(ExitPlanner.is_fork(sim, 100))
	assert_false(ExitPlanner.is_fork(sim, 200))
	assert_true(ExitPlanner.is_fork(sim, 50))
	assert_true(ExitPlanner.is_fork(sim, 150))


func test_each_boss_once_before_any_twice() -> void:
	var met := 0
	var seen := {}
	var rng := SimRng.new(12)
	for i in RoomCatalog.bosses().size():
		var b := RoomCatalog.pick_boss(rng, met)
		assert_false(seen.has(b), "not met before")
		seen[b] = true
		met |= RoomCatalog.boss_bit(b)
	assert_true(RoomCatalog.all()[RoomCatalog.pick_boss(rng, met)].boss)


func test_the_same_seed_meets_the_same_boss() -> void:
	var a := _into_boss(31)
	var b := _into_boss(31)
	assert_eq(a.room.index, b.room.index)
	assert_eq(a.checksum(), b.checksum())


func test_tiers_by_score() -> void:
	var sim := GameSim.new(4, Seasons.NONE, _boss_index("boss_saw"))
	assert_eq(SimConfig.boss_tier(sim.room.entry_score), 1)
	sim.state.score = 2 * SimConfig.BOSS_EVERY
	sim._enter_room(_boss_index("boss_saw"))
	assert_eq(SimConfig.boss_tier(sim.room.entry_score), 2)
	assert_eq(sim.room.spike_bonus(0), 1, "one more wall spike at tier 2")
	sim.state.score = 7 * SimConfig.BOSS_EVERY
	sim._enter_room(_boss_index("boss_saw"))
	assert_eq(SimConfig.boss_tier(sim.room.entry_score), 3)


func test_phases_change_on_the_bounces_and_the_boss_breaks_at_the_exit() -> void:
	var sim := _into_boss(55)
	var boss: Boss = sim.room.hazards[0]
	sim.state.arrival_hold = 0
	var coins := sim.state.coins
	for i in SimConfig.BOSS_POINTS:
		var p := boss.phase
		_bounce(sim)
		sim.room.step(sim)
		var want := 1 if i + 1 < Boss.PHASE_AT[0] else (2 if i + 1 < Boss.PHASE_AT[1] else 3)
		if i + 1 < SimConfig.BOSS_POINTS:
			assert_eq(boss.phase, want, "bounce %d" % (i + 1))
			assert_false(sim.state.exit_open, "no exit before the last bounce")
			if want != p:
				assert_true(boss.clock() < 0, "the boss waits after a phase change")
	assert_true(sim.state.exit_open, "the exit opens on the last bounce")
	assert_true(GameSim.Event.BOSS_DOWN in sim.events)
	assert_true(boss.down_at >= 0, "the boss broke")
	assert_eq(
		sim.state.coins - coins,
		SimConfig.BOSS_COINS[0],
		"the boss pays its coins (and the bounce coin is not taken here)"
	)
	assert_false(boss.kills(sim), "a broken boss never kills")


func test_no_attack_while_the_bird_reads_the_room() -> void:
	for id: String in ["boss_watcher", "boss_crusher", "boss_saw"]:
		for y_px: int in [120, 200, 320, 440, 520]:
			var sim := GameSim.new(3, Seasons.NONE, _boss_index(id))
			sim.state.anchor_y = y_px * SimConfig.SUB
			sim._enter_room(_boss_index(id))
			var boss: Boss = sim.room.hazards[0]
			for step in Boss.FIRST_DELAY + 59:
				sim.room.step(sim)
				sim.state.y = y_px * SimConfig.SUB
				for x_px: int in [20, 100, 180, 260, 340]:
					sim.state.x = x_px * SimConfig.SUB
					assert_false(
						boss.kills(sim), "%s kills at %d,%d step %d" % [id, x_px, y_px, step]
					)


func test_a_revive_in_a_boss_room_restarts_the_boss() -> void:
	var sim := _into_boss(91)
	sim.state.arrival_hold = 0
	var hold_score := sim.state.score
	for i in 9:
		_bounce(sim)
	for i in 50:
		sim.room.step(sim)
	sim.kill(SimState.DeathCause.HAZARD)
	assert_true(sim.revive())
	var boss: Boss = sim.room.hazards[0]
	assert_eq(sim.state.score, hold_score, "score as the bird came in")
	assert_eq(sim.room.points, 0)
	assert_eq(boss.phase, 1)
	assert_eq(boss.t, 0, "the boss starts over")
