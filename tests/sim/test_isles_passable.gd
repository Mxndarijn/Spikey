extends TestCase
## Floating Isles (and the Egg Hunt, which has the same islands) must always
## leave a way through: off the start, past the islands to the portal, into
## the next room, and after a revive. SurvivalSearch plays each case; the
## layout rules it relies on are checked on many more seeds without it.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const Block := preload("res://sim/hazards/block.gd")

## Practice seeds. 1 and 322 used to be impossible off the start (an island in
## the start lane, end to end with the one above it, 87 px between them).
const ISLES_SEEDS: Array[int] = [1, 322, 7, 2024, 31337]
const EGGS_SEEDS: Array[int] = [3, 58]
## Revive seeds, facing an open exit. One flight to reach it: one in ten used
## to be impossible (islands put back between the bird and the exit).
const REVIVE_SEEDS: Array[int] = [15, 127, 183]
## The practice score the searches start at: the walls are as full as they get
## (six spikes) and the next exit is planned on the first bounce.
const NEAR_EXIT := 28
## Two bounces, the flight into the portal, the wait in the new room and its
## first two seconds.
const PORTAL_TICKS := 450
## The portal wait, one flight across and a little of the next room.
const REVIVE_TICKS := SimConfig.ARRIVAL_HOLD + 110


## SurvivalSearch with a coarse (fast) first pass. A line it finds is a real
## way through; only when it finds none does the full search run.
class QuickSearch:
	extends SurvivalSearch

	func run(sim: GameSim, ticks: int) -> bool:
		level = -1
		_bucket_h = 10 * SimConfig.SUB
		_bucket_vy = -SimConfig.FLAP_VY / 2
		_speed_buckets = 4
		if _run_once(sim, ticks):
			return true
		return super.run(sim, ticks)


func test_isles_lead_through_the_portal() -> void:
	for s in ISLES_SEEDS:
		_must_pass_portal("isles", s)


func test_egg_hunt_leads_through_the_portal() -> void:
	for s in EGGS_SEEDS:
		_must_pass_portal("eggs", s)


func test_revived_bird_reaches_the_open_exit() -> void:
	for s in REVIVE_SEEDS:
		var sim := _revived("isles", s, "open", s % 2)
		var search := QuickSearch.new()
		var ok := search.run(sim, REVIVE_TICKS)
		assert_true(
			ok,
			(
				"isles seed %d: all died %d ticks after the revive (%s) %s"
				% [s, search.ticks_survived, search.last_deaths, _layout(sim)]
			)
		)
		if ok:
			assert_true(search.best.state.room_index > sim.state.room_index, "through the exit")


## Islands in neighbouring bands are far enough apart to hover between, or
## well clear of each other side to side.
func test_neighbouring_islands_leave_a_lane() -> void:
	for s in 300:
		for sim: GameSim in [_practice("isles", s), _arrived("isles", s)]:
			var islands := _islands(sim)
			for a: Block in islands:
				for b: Block in islands:
					if b.band != a.band + 1:
						continue
					var beside := b.x0 - a.x1 >= Block.PINCH_X or a.x0 - b.x1 >= Block.PINCH_X
					assert_true(
						beside or b.y0 - a.y1 >= Block.MIN_GAP,
						"seed %d: bands %d and %d pinch %s" % [s, a.band, b.band, _layout(sim)]
					)


## Before the first tap no island is on the bird's first hop or in its start lane.
func test_islands_keep_off_the_start() -> void:
	for s in 300:
		var sim := _practice("isles", s)
		for b: Block in _islands(sim):
			assert_false(
				FairLanes.start_path_hits_rect(sim, b.x0, b.y0, b.x1, b.y1, Block.START_MARGIN),
				"seed %d: island on the first hop" % s
			)
			assert_false(
				FairLanes.blocks_start_lane(sim, b.x0, b.y0, b.x1, b.y1),
				"seed %d: island in the lane" % s
			)


## Out of a portal the bird has clear room ahead: no island level with it
## within ARRIVAL_W of the wall it comes out of.
func test_islands_keep_off_the_arrival() -> void:
	for s in 300:
		var sim := _arrived("isles", s)
		var st := sim.state
		for b: Block in _islands(sim):
			var level := b.y1 > st.y - Block.ARRIVAL_UP and b.y0 < st.y + Block.ARRIVAL_DOWN
			var near := (
				b.x0 < Block.ARRIVAL_W if st.vx > 0 else b.x1 > SimConfig.WORLD_W - Block.ARRIVAL_W
			)
			assert_false(level and near, "seed %d: island in front of the arrival" % s)


## No exit is planned level with an island that sits near its wall.
func test_exits_open_clear_of_islands() -> void:
	var blocked := 0
	for s in 300:
		var sim := _practice("isles", s)
		var side := s % 2
		sim.state.exit_side = side
		var y := ExitPlanner.random_y(sim, sim._rng, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		for b: Block in _islands(sim):
			var away := b.x0 if side == 0 else SimConfig.WORLD_W - b.x1
			var level := absi(y - (b.y0 + b.y1) / 2) < (b.y1 - b.y0) / 2 + SimConfig.BIRD_RADIUS
			if away < Block.EXIT_CLEAR_X:
				blocked += 1
				assert_true(b.blocks_exit(sim, side, (b.y0 + b.y1) / 2), "level exit is blocked")
				assert_false(b.blocks_exit(sim, 1 - side, (b.y0 + b.y1) / 2), "far wall is fine")
			assert_false(
				away < Block.EXIT_CLEAR_X and level,
				"seed %d: exit at %d behind an island" % [s, y / SimConfig.SUB]
			)
	assert_true(blocked > 100, "islands near a wall came up (%d)" % blocked)


## A revive puts the islands back around the exit that is already there: none
## in front of it, and, when it is open, none between the bird and it.
func test_revive_keeps_the_way_to_the_exit_clear() -> void:
	for s in 200:
		var exit := "open" if s % 2 == 0 else "ghost"
		var sim := _revived("isles", s, exit, (s / 2) % 2)
		var st := sim.state
		for b: Block in _islands(sim):
			assert_false(
				b.blocks_exit(sim, st.exit_side, st.exit_a_y),
				"seed %d: island in front of the %s exit %s" % [s, exit, _layout(sim)]
			)
			if exit == "open":
				var top := mini(st.y, st.exit_a_y) - Block.ARRIVAL_UP
				var bottom := maxi(st.y + Block.ARRIVAL_DOWN, st.exit_a_y + Block.ARRIVAL_UP)
				assert_false(
					b.y1 > top and b.y0 < bottom,
					"seed %d: island between the bird and the exit %s" % [s, _layout(sim)]
				)


## Ghost Doors blocks stay where the catalog put them and block no exit.
func test_fading_blocks_are_unchanged() -> void:
	var sim := _practice("ghostdoors", 5)
	var doors := 0
	for h in sim.room.hazards:
		if h.kind != "block":
			continue
		var i := doors
		doors += 1
		assert_eq(h.x0, (90 + (i % 2) * 120) * SimConfig.SUB, "door %d x" % i)
		assert_eq(h.y0, (190 + (i / 2) * 130) * SimConfig.SUB, "door %d y" % i)
		assert_true(h.alive, "door %d is there" % i)
		for side in 2:
			assert_false(h.blocks_exit(sim, side, (h.y0 + h.y1) / 2), "doors block no exit")
	assert_true(doors > 0, "the room has doors")


## Plays practice room `id` from just before an exit is planned: some line of
## taps must get through the portal and on into the next room.
func _must_pass_portal(id: String, seed_value: int) -> void:
	var sim := _practice(id, seed_value)
	sim.state.score = NEAR_EXIT
	var search := QuickSearch.new()
	var ok := search.run(sim, PORTAL_TICKS)
	assert_true(
		ok,
		(
			"%s seed %d: all died at tick %d (%s) %s"
			% [id, seed_value, search.ticks_survived, search.last_deaths, _layout(sim)]
		)
	)
	if ok:
		assert_true(
			search.best.state.room_index >= 1, "%s seed %d: through the portal" % [id, seed_value]
		)


static func _practice(id: String, seed_value: int) -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	return GameSim.new(seed_value, def.season, index)


## A practice room entered again as through a portal: the bird comes out of a
## wall at a height and on a side the seed picks.
static func _arrived(id: String, seed_value: int) -> GameSim:
	var sim := _practice(id, seed_value)
	var rng := SimRng.new(seed_value + 7919)
	sim.state.started = true
	sim.state.y = (60 + rng.next_below(520)) * SimConfig.SUB
	var side := rng.next_below(2)
	sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	sim._enter_room(sim.practice_room)
	sim._arrive(side, GameSim.Event.ROOM_CHANGE)
	return sim


## A real run put in room `id` with an exit ("open" or "ghost") on wall
## `side`, killed there and revived.
static func _revived(id: String, seed_value: int, exit: String, side: int) -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	if exit == "open":
		sim.state.score = base
		sim._enter_room(index)
		ExitPlanner.plan(sim, sim._rng, side, base)
		sim.state.exit_open = true
	else:
		sim.state.score = base + every - 1
		sim._enter_room(index)
		ExitPlanner.plan(sim, sim._rng, side, base + every)
		sim.state.exit_preview = true
	sim.kill(SimState.DeathCause.HAZARD)
	sim.revive()
	return sim


static func _islands(sim: GameSim) -> Array[Block]:
	var out: Array[Block] = []
	for h in sim.room.hazards:
		if h.kind == "block" and h.alive:
			out.append(h as Block)
	return out


## The islands and the exit, in px, for a failure message.
static func _layout(sim: GameSim) -> String:
	var sub := SimConfig.SUB
	var st := sim.state
	var out := "[bird %d,%d" % [st.x / sub, st.y / sub]
	if st.exit_open or st.exit_preview:
		out += ", exit wall %d at %d" % [st.exit_side, st.exit_a_y / sub]
	for b in _islands(sim):
		out += ", island %d..%d x %d..%d" % [b.x0 / sub, b.x1 / sub, b.y0 / sub, b.y1 / sub]
	return out + "]"
