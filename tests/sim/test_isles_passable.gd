extends TestCase
## Floating Isles (and the Egg Hunt, which has the same islands) must always
## leave a way through, in every variant (still, drifting, one big rock): off
## the start, past the islands to the portal, into the next room, and after a
## revive. SurvivalSearch plays each case on FastSim (`tools/fastsim.ps1 -Mode
## check -Check isles`, part of tools/check.ps1); here the layout rules it
## relies on are checked on many seeds without it. A drifting island is checked
## over its whole sway (Block.drift each way of where it starts).

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const Block := preload("res://sim/hazards/block.gd")

const ISLES_VARIANTS: Array[String] = ["classic", "drifting", "one-big"]


## Islands in neighbouring bands are far enough apart to hover between, or
## well clear of each other side to side.
func test_neighbouring_islands_leave_a_lane() -> void:
	for s in 300:
		var v := ISLES_VARIANTS[s % ISLES_VARIANTS.size()]
		for sim: GameSim in [_practice("isles", s, v), _arrived("isles", s, v)]:
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
		var v := ISLES_VARIANTS[s % ISLES_VARIANTS.size()]
		var sim := _practice("isles", s, v)
		for b: Block in _islands(sim):
			var x0 := _sway_x0(b)
			var x1 := _sway_x1(b)
			assert_false(
				FairLanes.start_path_hits_rect(sim, x0, b.y0, x1, b.y1, Block.START_MARGIN),
				"%s seed %d: island on the first hop" % [v, s]
			)
			assert_false(
				FairLanes.blocks_start_lane(sim, x0, b.y0, x1, b.y1),
				"%s seed %d: island in the lane" % [v, s]
			)


## Out of a portal the bird has clear room ahead: no island level with it
## within ARRIVAL_W of the wall it comes out of.
func test_islands_keep_off_the_arrival() -> void:
	for s in 300:
		var v := ISLES_VARIANTS[s % ISLES_VARIANTS.size()]
		var sim := _arrived("isles", s, v)
		var st := sim.state
		for b: Block in _islands(sim):
			var level := b.y1 > st.y - Block.ARRIVAL_UP and b.y0 < st.y + Block.ARRIVAL_DOWN
			var near := (
				_sway_x0(b) < Block.ARRIVAL_W
				if st.vx > 0
				else _sway_x1(b) > SimConfig.WORLD_W - Block.ARRIVAL_W
			)
			assert_false(level and near, "%s seed %d: island in front of the arrival" % [v, s])


## No exit is planned level with an island that sits near its wall.
func test_exits_open_clear_of_islands() -> void:
	var blocked := 0
	for s in 300:
		var v := ISLES_VARIANTS[s % ISLES_VARIANTS.size()]
		var sim := _practice("isles", s, v)
		var side := s % 2
		sim.state.exit_side = side
		var y := ExitPlanner.random_y(sim, sim._rng, SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		for b: Block in _islands(sim):
			var away := _sway_x0(b) if side == 0 else SimConfig.WORLD_W - _sway_x1(b)
			var far := SimConfig.WORLD_W - _sway_x1(b) if side == 0 else _sway_x0(b)
			var level := absi(y - (b.y0 + b.y1) / 2) < (b.y1 - b.y0) / 2 + SimConfig.BIRD_RADIUS
			if away < Block.EXIT_CLEAR_X:
				blocked += 1
				assert_true(b.blocks_exit(sim, side, (b.y0 + b.y1) / 2), "level exit is blocked")
				if far >= Block.EXIT_CLEAR_X:
					assert_false(b.blocks_exit(sim, 1 - side, (b.y0 + b.y1) / 2), "far wall fine")
			assert_false(
				away < Block.EXIT_CLEAR_X and level,
				"%s seed %d: exit at %d behind an island" % [v, s, y / SimConfig.SUB]
			)
	assert_true(blocked > 100, "islands near a wall came up (%d)" % blocked)


## A revive puts the islands back around the exit that is already there: none
## in front of it, and, when it is open, none between the bird and it.
func test_revive_keeps_the_way_to_the_exit_clear() -> void:
	for s in 300:
		var exit := "open" if s % 2 == 0 else "ghost"
		var v := ISLES_VARIANTS[(s / 4) % ISLES_VARIANTS.size()]
		var sim := _revived("isles", s, exit, (s / 2) % 2, v)
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
	var sim := _practice("ghostdoors", 5, "classic")
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


static func _practice(id: String, seed_value: int, variant: String = "classic") -> GameSim:
	return BotSetups.practice(id, seed_value, variant)


## A practice room entered again as through a portal: the bird comes out of a
## wall at a height and on a side the seed picks.
static func _arrived(id: String, seed_value: int, variant: String = "classic") -> GameSim:
	var sim := _practice(id, seed_value, variant)
	var rng := SimRng.new(seed_value + 7919)
	sim.state.started = true
	sim.state.y = (60 + rng.next_below(520)) * SimConfig.SUB
	var side := rng.next_below(2)
	sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	sim._enter_room(sim.practice_room)
	sim._arrive(side, GameSim.Event.ROOM_CHANGE)
	return sim


static func _revived(
	id: String, seed_value: int, exit: String, side: int, variant: String = "classic"
) -> GameSim:
	return BotSetups.isles_revived(id, seed_value, exit, side, variant)


## Left and right edge of an island's whole sway (its box when it is still).
static func _sway_x0(b: Block) -> int:
	return b.home_x - b.drift


static func _sway_x1(b: Block) -> int:
	return b.home_x + (b.x1 - b.x0) + b.drift


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
