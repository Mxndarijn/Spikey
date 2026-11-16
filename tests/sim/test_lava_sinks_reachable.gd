extends TestCase
## Lava Rise's sinks can be taken: from the moment one comes out, a line takes
## it and lives on (the true future, a beam search). Slow: integration tier.
## The wall and lava clearances and the NZEGD-9QR0R case:
## tests/unit/test_lava_sinks_clear.gd.

const Clear := preload("res://tests/unit/test_lava_sinks_clear.gd")
const Lava := preload("res://sim/hazards/lava.gd")
## Practice seeds per variant searched.
const SEARCH_SEEDS := 3
## Ticks the search may take to reach a sink (several crossings), and ticks it
## must live on after taking it.
const REACH_TICKS := 360
const LIVE_AFTER := 60


static func _lava(sim: GameSim) -> Lava:
	return Clear._lava(sim)


## Whether a line from `sim` takes a sink (the lava's rises drop) within
## REACH_TICKS and lives LIVE_AFTER ticks more. A beam of copies, one per
## height-and-speed bucket, tries tap and wait every tick (the true future).
static func takes_sink(sim: GameSim) -> bool:
	var room := sim.state.room_kind
	var frontier: Array[GameSim] = [SimCopy.copy(sim)]
	for t in REACH_TICKS:
		var next := {}
		for s in frontier:
			var before := _lava(s).rises
			for tap: bool in [false, true]:
				if tap and s.state.vy < SurvivalSearch.TAP_BELOW_VY:
					continue
				var c := SimCopy.copy(s)
				c.step(tap)
				if c.is_over() or not c.state.alive or c.state.room_kind != room:
					continue
				if _lava(c).rises < before:
					if SurvivalSearch.new().run(c, LIVE_AFTER):
						return true
					continue
				var key := (c.state.y / (8 * SimConfig.SUB)) * 64 + c.state.vy / SimConfig.SUB
				if not next.has(key):
					next[key] = c
		frontier.assign(next.values())
		if frontier.is_empty():
			return false
	return false


func test_every_sink_can_be_taken_and_lived_past() -> void:
	var room := RoomCatalog.index_of("lava")
	for variant in Clear.VARIANTS:
		var searched := 0
		for s in SEARCH_SEEDS:
			var sim := Clear.to_sink(GameSim.new(2000 + s, Seasons.NONE, room, variant), s)
			if sim == null:
				continue
			searched += 1
			assert_true(takes_sink(sim), "%s seed %d: a line takes the sink" % [variant, s])
		assert_true(searched >= SEARCH_SEEDS - 1, "%s: sinks came out" % variant)


func test_seed_nzegd_9qr0r_ice_can_be_taken() -> void:
	var sim := Clear.to_sink(GameSim.new(Clear.NZEGD), 1)
	assert_true(sim != null and sim.room.variant_id() == "cold", "Cold Wall's ice is out")
	if sim != null:
		assert_true(takes_sink(sim), "a line takes the ice and lives on")
