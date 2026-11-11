extends TestCase
## Double Trouble's combo rules (sim/rooms/catalog_combo.gd): every pair keeps
## a way through. The full measurement is `tools/fastsim.ps1 -Mode combos`;
## the search over every pair runs on more seeds there too (`tools/fastsim.ps1
## -Mode check -Check pairs`, part of tools/check.ps1).

const Piston := preload("res://sim/hazards/piston.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const Drop := preload("res://sim/hazards/drop.gd")

const PARALLEL := true
const PARTS := 4
## Hazards that follow the bird add pressure to anything they share a room with.
const CHASERS: Array[String] = ["stalker"]
## Seeds searched per pair (FastSim: Checks.cs SEARCH_SEEDS), and how long
## the search must last.
const SEARCH_SEEDS := 1
const SEARCH_TICKS := 600


## A sim in Double Trouble playing pair `pair` (the first seed that draws it).
static func sim_with(pair: int, from_seed: int = 1) -> GameSim:
	var index := RoomCatalog.index_of("double")
	var def := RoomCatalog.all()[index]
	for s in range(from_seed, from_seed + 400):
		var sim := GameSim.new(s)
		sim.state.room_kind = index
		sim.room.start(def, index, sim, SimRng.new(s + 1))
		if sim.room.variant == pair:
			return sim
	return null


static func kinds_of(pair: Array) -> Array[String]:
	var out: Array[String] = []
	for f: Callable in pair:
		var h: Hazard = f.call()
		out.append(h.kind)
	return out


## Each pair's hazard factories (Double Trouble's variants).
static func pairs() -> Array:
	var out: Array = []
	for v: RoomVariant in RoomCatalog.find("double").variants:
		out.append(v.hazards)
	return out


func test_no_pair_has_a_chaser() -> void:
	for pair: Array in pairs():
		for k in kinds_of(pair):
			assert_false(k in CHASERS, "%s follows the bird: keep it out of combos" % k)


func test_every_warning_lasts_a_second() -> void:
	for pair: Array in pairs():
		for f: Callable in pair:
			var h: Hazard = f.call()
			if h is Piston:
				assert_true((h as Piston).glow_ticks >= SimConfig.ARRIVAL_BLIND, "piston glow")
			if h is Beam:
				assert_true((h as Beam).warn_ticks >= SimConfig.ARRIVAL_BLIND, "beam warning")
			if h is Drop:
				assert_true((h as Drop).warn >= SimConfig.ARRIVAL_BLIND, "rain mark")


func test_piston_slams_inside_the_other_hazards_band() -> void:
	for p in pairs().size():
		var sim := sim_with(p)
		var piston: Piston = null
		var other: Hazard = null
		for h: Hazard in sim.room.hazards:
			if h is Piston:
				piston = h
			elif h.band_top() >= 0:
				other = h
		if piston == null or other == null:
			continue
		var rng := SimRng.new(7)
		for i in 1200:
			sim.room.step(sim)
			if i % 70 == 0:
				piston.on_bounce(sim, rng)
			if piston.extent() > 0:
				assert_true(piston.y - Piston.HALF_H >= other.band_top(), "ram above the band")
				assert_true(piston.y + Piston.HALF_H <= other.band_bottom(), "ram below the band")


func test_a_live_beam_never_shares_a_row_with_the_ball() -> void:
	for p in pairs().size():
		var skipped := -1
		for from_seed: int in [1, 50, 120]:
			var sim := sim_with(p, from_seed)
			var beam: Beam = null
			var ball: Bouncer = null
			for h: Hazard in sim.room.hazards:
				if h is Beam:
					beam = h
				elif h is Bouncer:
					ball = h
			if beam == null or ball == null:
				break
			skipped = maxi(skipped, 0)
			for i in 1800:
				sim.room.step(sim)
				for r in beam.rows.size():
					skipped += beam.skip[r]
					if beam.state(r) == Beam.State.ON:
						var gap := absi(ball.y - beam.rows[r])
						assert_true(
							gap >= ball.radius + Beam.HALF_H + Beam.YIELD_GAP, "ball in a live row"
						)
		if skipped >= 0:
			assert_true(skipped > 0, "the beams sat out at least one turn")


func test_every_pair_has_a_way_through(part: int, parts: int) -> void:
	var index := RoomCatalog.index_of("double")
	var def: RoomDef = RoomCatalog.all()[index]
	var n := pairs().size()
	for i in range(part, n * SEARCH_SEEDS, parts):
		var p := i % n
		var found := 0
		# Practice seeds whose pair is `p`, by the hazards the room built.
		for s in range(1000 + i * 7, 3000):
			var sim := GameSim.new(s, def.season, index)
			if sim.room.variant != p:
				continue
			var search := SurvivalSearch.new()
			var ok := search.run(sim, SEARCH_TICKS)
			assert_true(ok, "pair %d seed %d: all died at tick %d" % [p, s, search.ticks_survived])
			found += 1
			break
		assert_eq(found, 1, "a seed for pair %d" % p)
