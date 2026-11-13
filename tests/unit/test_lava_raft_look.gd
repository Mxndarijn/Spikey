extends TestCase
## Lava Rise rafts, the look: the drawn top is the sim's surface, a raft the
## sim used up reads as landed on (the painter dips and sinks it, the bird
## squashes), and nothing of this reaches the sim.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const Lava := preload("res://sim/hazards/lava.gd")
const LavaPainter := preload("res://game/run/painters/lava_painter.gd")

const SUB := SimConfig.SUB


func _rafts(seed_value: int) -> GameSim:
	var sim := Rooms.sim_in_room("lava", seed_value)
	sim.state.started = true
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	l.draw_plan(SimRng.new(seed_value))
	l.rises = 3
	l.line = l.line_at(3)
	l.raft_on[0] = true
	l.raft_x[0] = 180 * SUB
	l.raft_age[0] = Lava.RAFT_RISE
	return sim


func test_the_drawn_top_is_the_sims_surface() -> void:
	var sim := _rafts(1)
	var l: Lava = sim.room.hazards[0]
	var line := HazardLayer.px(l.line)
	var surface := HazardLayer.px(l.line - Lava.RAFT_HIGH)
	assert_eq(LavaPainter.raft_top(l, 0, line), surface, "up: the top is where the bird lands")
	l.raft_age[0] = Lava.RAFT_RISE / 2
	assert_true(LavaPainter.raft_top(l, 0, line) > surface, "rising: still under the surface")


func test_a_raft_the_sim_used_up_was_landed_on() -> void:
	var sim := _rafts(2)
	var l: Lava = sim.room.hazards[0]
	var seen := {}
	assert_true(RaftLanding.landed(l, seen).is_empty(), "first look: nothing landed")
	sim.state.x = l.raft_x[0]
	sim.state.y = l.line - Lava.RAFT_HIGH - SimConfig.BIRD_RADIUS + SUB
	sim.state.vy = 4 * SUB
	l.touch(sim)
	assert_false(l.raft_on[0], "the sim used the raft up")
	assert_eq(RaftLanding.landed(l, seen), [0] as Array[int], "a landing")
	assert_true(RaftLanding.landed(l, seen).is_empty(), "only once")


func test_a_raft_still_rising_that_goes_is_no_landing() -> void:
	var sim := _rafts(3)
	var l: Lava = sim.room.hazards[0]
	l.raft_age[0] = Lava.RAFT_RISE - 5
	var seen := {}
	RaftLanding.landed(l, seen)
	l.raft_on[0] = false
	assert_true(RaftLanding.landed(l, seen).is_empty(), "not up yet: no landing")


func test_the_painter_draws_a_landed_raft_for_a_moment() -> void:
	var sim := _rafts(4)
	var l: Lava = sim.room.hazards[0]
	var p := LavaPainter.new()
	var line := HazardLayer.px(l.line)
	assert_eq(p.remember(l, line, 1.0), 0, "up, not landed")
	l.raft_on[0] = false
	assert_eq(p.remember(l, line, 1.1), 1, "landed")
	assert_true(p.landed_on(l, 0), "drawn dipping and sinking")
	p.remember(l, line, 1.1 + LavaPainter.USED_TIME + 0.1)
	assert_false(p.landed_on(l, 0), "gone once it has sunk")


func test_a_new_raft_replaces_a_landed_one() -> void:
	var sim := _rafts(5)
	var l: Lava = sim.room.hazards[0]
	var p := LavaPainter.new()
	var line := HazardLayer.px(l.line)
	p.remember(l, line, 0.0)
	l.raft_on[0] = false
	p.remember(l, line, 0.1)
	l.raft_on[0] = true
	l.raft_age[0] = 0
	p.remember(l, line, 0.2)
	assert_false(p.landed_on(l, 0), "the new raft is drawn, not the old one")


func test_the_bird_squashes_on_a_raft_landing() -> void:
	var sim := _rafts(6)
	var l: Lava = sim.room.hazards[0]
	var bird := BirdView.new()
	assert_false(bird.watch_rafts(sim), "nothing yet")
	l.raft_on[0] = false
	assert_true(bird.watch_rafts(sim), "a landing")
	assert_true(bird._land > 0.0, "the body squashes")
	bird.free()


func test_the_look_never_changes_the_sim() -> void:
	var sim := _rafts(7)
	var l: Lava = sim.room.hazards[0]
	var before := sim.checksum()
	var p := LavaPainter.new()
	var bird := BirdView.new()
	p.remember(l, HazardLayer.px(l.line), 0.0)
	bird.watch_rafts(sim)
	l.raft_on[0] = false
	var after_use := sim.checksum()
	p.remember(l, HazardLayer.px(l.line), 0.1)
	bird.watch_rafts(sim)
	assert_ne(before, after_use, "the test changed the sim itself")
	assert_eq(sim.checksum(), after_use, "watching it changed nothing")
	bird.free()


func test_lava_over_an_exit_shows_it_is_covered() -> void:
	var sim := _rafts(8)
	assert_true(LavaPainter.shown_exits(sim).is_empty(), "no exit shown yet")
	sim.state.exit_open = true
	sim.state.exit_side = 1
	sim.state.exit_a_y = 500 * SUB
	sim.state.exit_b_kind = SimState.ExitKind.NORMAL
	var shown := LavaPainter.shown_exits(sim)
	assert_eq(shown.size(), 1, "the open exit")
	assert_true(LavaPainter.covers(520.0, shown[0].y), "lava at 520 px covers an exit at 500")
	assert_false(LavaPainter.covers(560.0, shown[0].y), "lava at 560 px is under it")
