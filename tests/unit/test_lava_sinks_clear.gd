extends TestCase
## Lava Rise's sinks (the stone, Cold Wall's ice, the rafts) keep clear of both
## walls and stay above the lava (that a line takes them:
## tests/sim/test_lava_sinks_reachable.gd, integration tier).
## Seed NZEGD-9QR0R (v24, random 4221621471): its room 2 was Cold Wall. The ice
## sat in a right-wall slot, and since a bounce redraws the wall the bird
## leaves, that wall's spikes were drawn before the ice was put there: slot 7,
## next to the ice's slot 8, had a spike, and over 1000 practice seeds 23% of
## the ice blocks sat on a spiked slot. Now the ice hangs ICE_OFF off the wall
## the bird flies to and is taken mid-crossing.

const Lava := preload("res://sim/hazards/lava.gd")
const VARIANTS: Array[String] = ["lava", "cold", "rafts"]
## Practice seeds per variant whose sinks are checked against the walls and
## the lava.
const SEEDS := 12
## A bird touching a sink keeps this far clear of the deepest wall spike.
const MARGIN := 16 * SimConfig.SUB
const NZEGD := 4221621471


static func _lava(sim: GameSim) -> Lava:
	for h in sim.room.hazards:
		if h is Lava:
			return h
	return null


## Boxes (x0, y0, x1, y1) of the sinks that are out now.
static func sink_boxes(sim: GameSim) -> Array[PackedInt64Array]:
	var l := _lava(sim)
	var out: Array[PackedInt64Array] = []
	if l == null:
		return out
	if l.stone_on:
		var r := Lava.STONE_RADIUS
		out.append(PackedInt64Array([l.stone_x - r, l.stone_y - r, l.stone_x + r, l.stone_y + r]))
	if l.ice_on:
		out.append(PackedInt64Array([l.ice_x0(sim), l.ice_y0(), l.ice_x1(sim), l.ice_y1()]))
	for i in Lava.MAX_RAFTS:
		if l.raft_on[i]:
			var top := l.line - Lava.RAFT_HIGH
			out.append(
				PackedInt64Array([l.raft_x[i] - Lava.RAFT_HALF, top, l.raft_x[i] + Lava.RAFT_HALF, l.line])
			)
	return out


## Plays a gap seeker in practice until a sink comes out (or `limit` ticks).
## Returns the sim then, or null.
static func to_sink(sim: GameSim, bot_seed: int, limit: int = 4000) -> GameSim:
	var rng := SimRng.new(bot_seed)
	while not sim.is_over() and sim.state.tick < limit:
		var had := sink_boxes(sim).size()
		sim.step(SimBots.gap_seeker(sim, rng))
		if sink_boxes(sim).size() > had and not sim.is_over():
			return sim
	return null


func _check_clear(sim: GameSim, what: String) -> void:
	var l := _lava(sim)
	var band := sim.room.max_spike_depth() + 2 * SimConfig.BIRD_RADIUS + MARGIN
	for b in sink_boxes(sim):
		var gap := mini(b[0] - sim.room.wall_left(), sim.room.wall_right() - b[2])
		assert_true(
			gap >= band, "%s: a sink %d px off a wall" % [what, gap / SimConfig.SUB]
		)
	if l.stone_on or l.ice_on:
		var bottom := l.stone_y + Lava.STONE_RADIUS if l.stone_on else l.ice_y1()
		var full := l.line <= SimConfig.KILL_TOP + Lava.STONE_EDGE + Lava.STONE_CLEAR
		assert_true(
			full or bottom <= l.line - 2 * SimConfig.BIRD_RADIUS,
			"%s: the sink is in reach above the lava" % what
		)


func test_every_sink_keeps_clear_of_the_walls_and_the_lava() -> void:
	var room := RoomCatalog.index_of("lava")
	for variant in VARIANTS:
		var seen := 0
		for s in SEEDS:
			var sim := GameSim.new(1000 + s, Seasons.NONE, room, variant)
			var rng := SimRng.new(s)
			while not sim.is_over() and sim.state.tick < 3000 and sim.state.room_kind == room:
				sim.step(SimBots.gap_seeker(sim, rng))
				if not sink_boxes(sim).is_empty():
					seen += 1
					_check_clear(sim, "%s seed %d tick %d" % [variant, s, sim.state.tick])
		assert_true(seen > 0, "%s: sinks came out" % variant)


## The run of the report: room 2 is Cold Wall; its ice hangs off the wall, in
## reach (the search: tests/sim/test_lava_sinks_reachable.gd).
func test_seed_nzegd_9qr0r_cold_wall_ice_is_off_the_wall() -> void:
	var parts := SeedCode.decode("NZEGD-9QR0R")
	assert_eq(parts.random, NZEGD, "the seed's random part")
	var sim := to_sink(GameSim.new(NZEGD, parts.season), 1)
	assert_true(sim != null, "the run reaches a sink")
	if sim == null:
		return
	assert_eq(sim.room.def.id, "lava", "Lava Rise")
	assert_eq(sim.room.variant_id(), "cold", "Cold Wall")
	assert_eq(sim.state.score / SimConfig.POINTS_PER_ROOM, 1, "room 2")
	var l := _lava(sim)
	assert_true(l.ice_on, "the ice is out")
	_check_clear(sim, "NZEGD")
