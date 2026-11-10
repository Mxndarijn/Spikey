extends TestCase
## Exit portals: every 10 points an exit opens on the wall ahead; flying into it
## moves to the next room, and the bird flies straight on into it. Every 50
## points a fork offers a Calm and a Wild exit. One point before an exit
## opens, it shows as a ghost on the wall and at the height it will open at.

const RoomsTest := preload("res://tests/unit/test_rooms.gd")
const Gate := preload("res://sim/hazards/gate.gd")


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
	assert_eq(sim.wall_mask(0) & ExitPlanner.slots(sim.state), 0, "no spike in the opening")
	var plain := _sim_at(4)
	_hit_wall(plain, 1, 300 * SimConfig.SUB)
	assert_false(plain.state.exit_open, "no exit at 5")


func test_the_exit_wall_is_spiked_everywhere_but_the_openings() -> void:
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	for start in [[9, 3], [49, 8]]:
		var sim := _sim_at(start[0], start[1])
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		assert_true(sim.state.exit_open)
		var openings := ExitPlanner.slots(sim.state)
		assert_ne(openings, 0, "the exit frees some slots")
		assert_eq(sim.wall_mask(0), all & ~openings, "every other slot has a spike")
		assert_ne(sim.wall_mask(1), all, "the wall without the exit is a normal wall")
	var missed := _sim_at(9)
	_hit_wall(missed, 1, 300 * SimConfig.SUB)
	var y := missed.state.exit_a_y
	# Four slots away: level with a spike's tip.
	var away := SimConfig.SLOT_SIZE * 4
	missed.state.y = y + away if y < 320 * SimConfig.SUB else y - away
	missed.state.vy = 0
	missed.state.vx = -SimConfig.SPEED_X
	missed.state.x = missed.room.wall_left() + SimConfig.BIRD_RADIUS + SimConfig.SPIKE_DEPTH / 2
	missed._check_spikes()
	assert_false(missed.state.alive, "missing the exit hits a spike")


func test_flying_through_moves_to_the_next_room() -> void:
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
	var t := sim.room.t
	sim.step(true)
	assert_true(GameSim.Event.FLAP in sim.events, "taps work from the first tick")
	assert_eq(sim.room.t, t + 1, "no wait and no slow motion")


## Out of a portal, Floating Isles keeps its islands out of the lane in front
## of the portal, and Shutter Gates has the gap at the bird when
## it reaches the nearer gate.
func test_isles_and_gates_leave_the_way_out_of_a_portal_open() -> void:
	var isles := RoomCatalog.index_of("isles")
	var gates := RoomCatalog.index_of("gates")
	var lane_ok := 0
	for i in 40:
		var y := (150 + (i * 53) % 340) * SimConfig.SUB
		var sim := _sim_at(20, 100 + i)
		sim.state.y = y
		sim._arrive_in(i % 2, isles)
		var clear := true
		for h in sim.room.hazards:
			if h.alive and h.kind == "block" and h._blocks_arrival(sim, h.x0, h.y0, h.x1, h.y1):
				clear = false
		if clear:
			lane_ok += 1
		var g := _sim_at(20, 100 + i)
		g.state.y = y
		g._arrive_in(i % 2, gates)
		var near: Hazard = g.room.hazards[0]
		for h in g.room.hazards:
			if absi(h.x - g.state.x) < absi(near.x - g.state.x):
				near = h
		var steps := absi(near.x - g.state.x) / SimConfig.SPEED_X
		# The gate's own range and hover: the room rework moved them (a taller gap).
		var want := clampi(y - Gate.ARRIVAL_HOVER, Gate.GAP_MIN_Y, Gate.GAP_MAX_Y)
		assert_true(absi(near.gap_at(steps) - want) <= 2 * SimConfig.SUB, "gate gap at the bird")
	assert_eq(lane_ok, 40, "isles lane clear in every arrival")


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


func test_missing_the_exit_bounces_without_a_point_and_it_stays_open() -> void:
	var sim := _sim_at(9)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var y := sim.state.exit_a_y
	var away := (
		y + SimConfig.EXIT_HALF * 2 if y < 320 * SimConfig.SUB else y - SimConfig.EXIT_HALF * 2
	)
	var room_before := sim.state.room_index
	_hit_wall(sim, 0, away)
	assert_eq(sim.state.score, 10, "no point while the exit is open")
	assert_true(GameSim.Event.BOUNCE in sim.events, "still a bounce")
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
	for score in [9, 49, 8, 48]:
		run.new_run(3)
		run.sim.step(true)
		run.sim.state.score = score
		_hit_wall(run.sim, 1, 300 * SimConfig.SUB)
		assert_true(run.sim.state.exit_open or run.sim.state.exit_preview)
		view.bind(run, ThemeCatalog.default_theme())
		for i in 4:
			await tree.process_frame
	run.free()
	view.free()


## Every height on an exit wall either goes through the exit or hits a spike:
## there is no strip beside the portal to bounce in and score.
func test_no_safe_bounce_between_portal_and_spike() -> void:
	for start in [[9, 3], [19, 5], [29, 11], [49, 8]]:
		var opened := _sim_at(start[0], start[1])
		_hit_wall(opened, 1, 300 * SimConfig.SUB)
		assert_true(opened.state.exit_open)
		var y := SimConfig.slot_center_y(0)
		while y <= SimConfig.slot_center_y(SimConfig.SLOT_COUNT - 1):
			var sim := _sim_at(start[0], start[1])
			_hit_wall(sim, 1, 300 * SimConfig.SUB)
			var r := SimConfig.BIRD_RADIUS
			sim.state.y = y
			sim.state.vy = 0
			sim.state.vx = -SimConfig.SPEED_X
			sim.state.x = sim.room.wall_left() + r - 1
			sim.events.clear()
			sim._check_spikes()
			if sim.state.alive:
				sim._check_walls()
				assert_true(
					GameSim.Event.ROOM_CHANGE in sim.events,
					"y %d px: through the exit, not a bounce" % (y / SimConfig.SUB)
				)
			y += SimConfig.SUB


func test_exits_sit_on_slot_centers_with_the_portal_in_the_middle() -> void:
	for start in [[9, 3], [19, 5], [29, 11], [49, 8]]:
		var sim := _sim_at(start[0], start[1])
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		var s := sim.state
		var ys := [s.exit_a_y]
		if s.exit_b_kind != SimState.ExitKind.NORMAL:
			ys.append(s.exit_b_y)
		for ey: int in ys:
			var slot := (ey - SimConfig.slot_center_y(0)) / SimConfig.SLOT_SIZE
			assert_eq(SimConfig.slot_center_y(slot), ey, "on a slot center")
			var three := 0b111 << (slot - 1)
			assert_eq(ExitPlanner.slots(sim.state) & three, three, "that slot and one either side")


## Coming out of a portal, the player hasn't seen the room yet: the gap ahead
## stays at the bird's height, and the other one stays reachable from it.
func test_stalactite_gap_ahead_stays_at_bird_height_after_a_portal() -> void:
	for seed_value in 12:
		for heading_right in [true, false]:
			var y := (130 + seed_value * 35) * SimConfig.SUB
			var sim := RoomsTest.sim_in_room("stalac", 50 + seed_value, Seasons.NONE, "classic")
			sim.state.started = true
			sim.state.y = y
			sim.state.vx = SimConfig.SPEED_X if heading_right else -SimConfig.SPEED_X
			var rocks: Array[Hazard] = []
			for h in sim.room.hazards:
				if h.kind == "stalactite":
					rocks.append(h)
			for h in rocks:
				h.setup(sim, SimRng.new(seed_value))
			for h in rocks:
				h.on_bounce(sim, SimRng.new(200 + seed_value))
			var near: Hazard = rocks[0] if heading_right == (rocks[0].x < rocks[1].x) else rocks[1]
			var far: Hazard = rocks[1] if near == rocks[0] else rocks[0]
			var want := clampi(y, 150 * SimConfig.SUB, 490 * SimConfig.SUB)
			assert_eq(near.target_y, want, "gap ahead at the bird's height")
			assert_eq(near.gap_y, want, "and already there")
			var step := absi(far.target_y - near.target_y)
			assert_true(step <= 60 * SimConfig.SUB, "next gap reachable")


## Turning back from an open exit (here off the Bumper Cloud) and bouncing off
## the far wall scores nothing, so the points can't be farmed.
func test_no_points_while_an_exit_is_open() -> void:
	var sim := _sim_at(9)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	assert_true(sim.state.exit_open)
	var score := sim.state.score
	sim.state.right_spikes = 0
	for i in 5:
		sim.bump_bird_from(sim.state.x - SimConfig.SUB, sim.state.y)
		assert_true(sim.state.vx > 0, "the bump turns it away from the exit")
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		assert_false(GameSim.Event.SCORE in sim.events, "no point for the far wall")
		assert_true(GameSim.Event.BOUNCE in sim.events)
		sim.state.right_spikes = 0
	assert_eq(sim.state.score, score, "the score stays put")
	assert_true(sim.state.exit_open, "the exit is still there")
	var after := _sim_at(9)
	_hit_wall(after, 1, 300 * SimConfig.SUB)
	_hit_wall(after, 0, after.state.exit_a_y)
	assert_false(after.state.exit_open)
	_hit_wall(after, 0, 300 * SimConfig.SUB)
	assert_eq(after.state.score, score + 1, "points come back in the next room")


func test_ghost_shows_one_point_early_where_the_exit_opens() -> void:
	var sim := _sim_at(8)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var s := sim.state
	assert_eq(s.score, 9)
	assert_true(s.exit_preview, "a ghost at 9")
	assert_false(s.exit_open, "not open yet")
	assert_true(GameSim.Event.EXIT_PREVIEW in sim.events)
	assert_false(GameSim.Event.EXIT_OPEN in sim.events)
	assert_eq(s.exit_side, 1, "on the wall the bird just bounced off")
	assert_true(s.copy().exit_preview, "the ghost is part of the state")
	var y := s.exit_a_y
	assert_between(y, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
	_hit_wall(sim, 0, 300 * SimConfig.SUB)
	assert_eq(s.score, 10)
	assert_true(s.exit_open, "it opens at 10")
	assert_false(s.exit_preview)
	assert_true(GameSim.Event.EXIT_OPEN in sim.events)
	assert_eq(s.exit_side, 1, "on the ghost's wall")
	assert_eq(s.exit_a_y, y, "at the ghost's exact height")
	_hit_wall(sim, 1, y)
	assert_true(GameSim.Event.ROOM_CHANGE in sim.events, "and it leads through")


func test_the_ghost_spot_is_spike_free_and_a_normal_bounce() -> void:
	for seed_value in 10:
		var sim := _sim_at(8, seed_value)
		_hit_wall(sim, 1, 300 * SimConfig.SUB)
		assert_true(sim.state.exit_preview)
		sim.state.right_spikes = (1 << SimConfig.SLOT_COUNT) - 1
		assert_eq(sim.wall_mask(1) & ExitPlanner.slots(sim.state), 0, "no spike in the ghost")
		assert_ne(sim.wall_mask(1), 0, "the rest of the wall keeps its spikes")
	# Turned back (Bumper Cloud) onto the ghost before point 10.
	var back := _sim_at(8)
	_hit_wall(back, 1, 300 * SimConfig.SUB)
	var y := back.state.exit_a_y
	var room_before := back.state.room_index
	_hit_wall(back, 1, y)
	assert_eq(back.state.room_index, room_before, "no way through a ghost")
	assert_true(GameSim.Event.BOUNCE in back.events, "a normal bounce")
	assert_true(GameSim.Event.SCORE in back.events, "worth its point")
	assert_eq(back.state.score, 10)
	assert_true(back.state.exit_open, "the exit opens")
	assert_eq(back.state.exit_side, 1, "on the ghost's wall, behind the bird")
	assert_eq(back.state.exit_a_y, y, "at the ghost's height")
	assert_true(back.state.vx < 0, "the bird is flying away from it")
	_hit_wall(back, 1, y)
	assert_eq(back.state.room_index, room_before + 1, "coming back, it leads through")


func test_a_fork_shows_both_ghosts() -> void:
	var sim := _sim_at(48, 8)
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	var s := sim.state
	assert_true(s.exit_preview)
	var kinds := [s.exit_a_kind, s.exit_b_kind]
	assert_true(SimState.ExitKind.CALM in kinds and SimState.ExitKind.WILD in kinds)
	var ys := [s.exit_a_y, s.exit_b_y]
	_hit_wall(sim, 0, 300 * SimConfig.SUB)
	assert_true(s.exit_open)
	assert_eq([s.exit_a_y, s.exit_b_y], ys, "both open where their ghosts were")
	assert_eq([s.exit_a_kind, s.exit_b_kind], kinds, "with the same kinds")


func test_practice_shows_a_ghost_without_forks() -> void:
	var index := RoomCatalog.index_of("pinwheel")
	var sim := GameSim.new(5, Seasons.NONE, index)
	sim.step(true)
	sim.state.score = 48
	_hit_wall(sim, 1, 300 * SimConfig.SUB)
	assert_true(sim.state.exit_preview)
	assert_eq(sim.state.exit_b_kind, SimState.ExitKind.NORMAL, "no forks in practice")
