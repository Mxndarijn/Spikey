extends TestCase
## Exit portals: every 10 points an exit opens on the wall ahead; flying into it
## moves to the next room, and the bird flies straight on into it. Every 50
## points a fork offers a Calm and a Wild exit.


## A run already at `score`, heading right, about to bounce off the left wall.
static func _sim_at(score: int, seed_value: int = 3) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.step(true)
	sim.state.score = score
	return sim


## Moves the bird onto the given wall at height y and runs the wall check.
static func _hit_wall(sim: GameSim, side: int, y: int) -> void:
	var r := SimConfig.BIRD_RADIUS
	sim.state.y = y
	sim.state.vy = 0
	if side == 1:
		sim.state.vx = SimConfig.SPEED_X
		sim.state.x = sim.room.wall_right() - r + 1
	else:
		sim.state.vx = -SimConfig.SPEED_X
		sim.state.x = sim.room.wall_left() + r - 1
	sim.events.clear()
	sim._check_walls()


func test_exit_opens_every_ten_points_on_the_wall_ahead() -> void:
	var sim := _sim_at(9)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	assert_eq(sim.state.score, 10)
	assert_true(sim.state.exit_open, "an exit opens at 10")
	assert_eq(sim.state.exit_side, 0, "on the wall the bird now heads to")
	assert_true(GameSim.Event.EXIT_OPEN in sim.events)
	assert_between(sim.state.exit_a_y, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
	assert_eq(sim.wall_mask(0) & sim.exit_slots(), 0, "no spike in the opening")
	var plain := _sim_at(4)
	_hit_wall(plain, 1, 300 * SimConfig.SUB)
	assert_false(plain.state.exit_open, "no exit at 5")


func test_the_exit_wall_is_spiked_everywhere_but_the_openings() -> void:
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	for start in [[9, 3], [49, 8]]:
		var sim := _sim_at(start[0], start[1])
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		assert_true(sim.state.exit_open)
		var openings := sim.exit_slots()
		assert_ne(openings, 0, "the exit frees some slots")
		assert_eq(sim.wall_mask(0), all & ~openings, "every other slot has a spike")
		assert_ne(sim.wall_mask(1), all, "the wall without the exit is a normal wall")
	var missed := _sim_at(9)
	_hit_wall(missed, 1, 300 * SimConfig.SUB)
	var y := missed.state.exit_a_y
	missed.state.y = (
		y + SimConfig.EXIT_HALF * 3 if y < 320 * SimConfig.SUB else y - SimConfig.EXIT_HALF * 3
	)
	missed.state.vy = 0
	missed.state.vx = -SimConfig.SPEED_X
	missed.state.x = missed.room.wall_left() + SimConfig.BIRD_RADIUS + SimConfig.SPIKE_DEPTH / 2
	missed._check_spikes()
	assert_false(missed.state.alive, "missing the exit hits a spike")


func test_flying_through_moves_to_the_next_room_without_stopping() -> void:
	var sim := _sim_at(9)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var room_before := sim.state.room_index
	var score := sim.state.score
	var y := sim.state.exit_a_y
	_hit_wall(sim, 0, y)
	assert_eq(sim.state.room_index, room_before + 1, "a new room")
	assert_true(GameSim.Event.ROOM_CHANGE in sim.events)
	assert_eq(sim.state.score, score, "no point for going through")
	assert_false(sim.state.exit_open)
	assert_eq(sim.state.y, y, "it keeps its height")
	assert_true(sim.state.vx < 0, "it keeps flying the same way (left)")
	var r := SimConfig.BIRD_RADIUS
	assert_eq(sim.state.x, sim.room.wall_right() - r, "out of the opposite (right) wall")
	assert_eq(sim.state.right_spikes, 0, "no spikes on the wall it came out of")
	assert_true(sim.state.left_spikes != 0, "the wall ahead has spikes again")
	var x := sim.state.x
	var t := sim.room.t
	sim.step(false)
	assert_true(sim.state.x < x, "it keeps flying")
	assert_true(sim.room.t > t, "the new room runs right away")


func test_the_bird_comes_out_flying_level() -> void:
	for vy in [SimConfig.MAX_FALL_VY, SimConfig.FLAP_VY]:
		var sim := _sim_at(9)
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		var room_before := sim.state.room_index
		var r := SimConfig.BIRD_RADIUS
		sim.state.y = sim.state.exit_a_y
		sim.state.vy = vy
		sim.state.vx = -SimConfig.SPEED_X
		sim.state.x = sim.room.wall_left() + r - 1
		sim._check_walls()
		assert_eq(sim.state.room_index, room_before + 1, "through the exit")
		assert_eq(sim.state.vy, 0, "level, not falling or rising (was %d)" % vy)


func test_missing_the_exit_is_a_normal_bounce_and_it_stays_open() -> void:
	var sim := _sim_at(9)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var y := sim.state.exit_a_y
	var away := (
		y + SimConfig.EXIT_HALF * 2 if y < 320 * SimConfig.SUB else y - SimConfig.EXIT_HALF * 2
	)
	var room_before := sim.state.room_index
	_hit_wall(sim, 0, away)
	assert_eq(sim.state.score, 11, "the bounce scores")
	assert_eq(sim.state.room_index, room_before, "same room")
	assert_true(sim.state.exit_open, "the exit is still there")


func test_fork_every_fifty_points_sets_the_route() -> void:
	var sim := _sim_at(49, 8)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var s := sim.state
	assert_true(s.exit_open)
	assert_ne(s.exit_b_kind, SimState.ExitKind.NORMAL, "two exits at 50")
	var kinds := [s.exit_a_kind, s.exit_b_kind]
	assert_true(SimState.ExitKind.CALM in kinds and SimState.ExitKind.WILD in kinds)
	assert_true(s.exit_a_y < SimConfig.FORK_SPLIT_Y and s.exit_b_y > SimConfig.FORK_SPLIT_Y)
	var wild_y := s.exit_a_y if s.exit_a_kind == SimState.ExitKind.WILD else s.exit_b_y
	var coins := s.coins
	_hit_wall(sim, 0, wild_y)
	assert_eq(sim.state.route, SimState.ExitKind.WILD, "the Wild route is set")
	assert_eq(sim.state.coins, coins + SimConfig.WILD_COINS, "Wild pays coins")
	var def := RoomCatalog.all()[sim.state.room_kind]
	assert_true(def.group in RoomCatalog.WILD_GROUPS, "a Wild room (%s)" % def.group)


func test_routes_limit_the_room_groups() -> void:
	var rng := SimRng.new(4)
	for i in 100:
		var calm := RoomCatalog.all()[RoomCatalog.pick_next(rng, 0, 200, Seasons.NONE, 1)]
		assert_true(calm.group in RoomCatalog.CALM_GROUPS, "calm %s" % calm.group)
		var wild := RoomCatalog.all()[RoomCatalog.pick_next(rng, 0, 200, Seasons.NONE, 2)]
		assert_true(wild.group in RoomCatalog.WILD_GROUPS, "wild %s" % wild.group)


func test_practice_exits_lead_back_to_the_same_room() -> void:
	var index := RoomCatalog.index_of("pinwheel")
	var sim := GameSim.new(5, Seasons.NONE, index)
	sim.step(true)
	sim.state.score = RoomCatalog.all()[index].from_score + 9
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	assert_true(sim.state.exit_open)
	assert_eq(sim.state.exit_b_kind, SimState.ExitKind.NORMAL, "no forks in practice")
	_hit_wall(sim, 0, sim.state.exit_a_y)
	assert_eq(sim.state.room_kind, index, "practice repeats its room")


func test_a_good_player_reaches_new_rooms() -> void:
	var seeds := SimRng.new(12)
	var rooms := 0
	for i in 20:
		var replay := SimBots.play(seeds.next_u32(), SimBots.gap_seeker, i + 1)
		var sim := Replay.simulate(replay.seed_value, replay.taps)
		rooms = maxi(rooms, sim.state.room_index)
	assert_true(rooms >= 1, "the bot flew through at least one exit (%d)" % rooms)


## Draws the room with a normal exit and a fork for a few frames (catches
## errors in the portal art).
func test_portals_draw() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var run := RunController.new()
	var view := RoomView.new()
	tree.root.add_child(run)
	tree.root.add_child(view)
	for score in [9, 49]:
		run.new_run(3)
		run.sim.step(true)
		run.sim.state.score = score
		_hit_wall(run.sim, 1, 300 * SimConfig.SUB)
		assert_true(run.sim.state.exit_open)
		view.bind(run, ThemeCatalog.default_theme())
		for i in 4:
			await tree.process_frame
	run.free()
	view.free()
