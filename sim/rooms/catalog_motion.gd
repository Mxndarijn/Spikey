extends RefCounted
## Rooms batch: motion. Things that move on a fixed path or follow the bird.
## Order is part of the rules (see RoomCatalog).

const Bumper := preload("res://sim/hazards/bumper.gd")
const Gate := preload("res://sim/hazards/gate.gd")
const Crawler := preload("res://sim/hazards/crawler.gd")
const Pendulum := preload("res://sim/hazards/pendulum.gd")
const Stalker := preload("res://sim/hazards/stalker.gd")
const Rotor := preload("res://sim/hazards/rotor.gd")
const SawRing := preload("res://sim/hazards/saw_ring.gd")

const SUB := SimConfig.SUB
## Shutter Gates, single: steps per up-and-down cycle (twice the pair's pace).
const SINGLE_PERIOD := 380
## Pinwheel variants, in draw order.
const PINWHEELS: Array[String] = ["trim", "three", "twin", "rock", "lean", "breathe"]
## Saw Ring variants, in draw order.
const SAW_RINGS: Array[String] = ["classic", "two-rings", "off-centre", "oval", "pair"]


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Bumper Cloud: a cloud on a slow loop; safe, but it shoves the bird away.
	# Variants: one cloud, or two on opposite sides of the loop.
	var cloud := RoomDef.new("cloud", "starter", 10)
	cloud.hazards.append(func() -> Hazard: return Bumper.new())
	cloud.variants = [
		RoomVariant.new("one"),
		RoomVariant.new("two").with([func() -> Hazard: return Bumper.new(true)]),
	]
	out.append(cloud)

	# Shutter Gates: two columns whose gaps slide up and down together, the
	# second a moment behind the first, like one moving tunnel.
	var gates := RoomDef.new("gates", "starter", 20)
	gates.max_spikes = 6
	# Variants: the two columns; one faster gate in the middle. Both are
	# GENERATED and keep one fixed layout all room: the window is wide enough
	# for the band a bird holding its height anywhere in the exit sweeps
	# (Gate.wide), and out of a portal the gates are timed once, at the start,
	# so every window is on that band while the bird flies past
	# (Gate.fit_arrival). Nothing opens or closes.
	gates.variants = [
		RoomVariant.new("classic").generated(_gen_gates.bind(false)),
		RoomVariant.new("single").generated(_gen_gates.bind(true)),
	]
	out.append(gates)

	# Caterpillar Crawl: crawlers walk round the inside of the cage. Every
	# variant is GENERATED: out of a portal the crawlers' starting places are
	# drawn again until none meets a bird holding its height (a crawler walks
	# the ceiling, so a high arrival needed it); see crawl_variants.
	var crawl := RoomDef.new("crawl", "starter", 30)
	crawl.variants = crawl_variants()
	out.append(crawl)

	# Lantern Swing: lanterns on chains swing from the ceiling. Variants: one
	# big lantern; twins swinging opposite ways; a row of three small ones on
	# their own beats; a gusty swing that grows and shrinks; a winch that winds
	# the chain up and down. Every lantern stays inside x 40..320 px (clear of
	# a bird at either wall) and moves slower than the bird.
	# Every variant is GENERATED (_gen_swing): the lanterns time their swing
	# to the arrival as before, the layout is checked and drawn again, and the
	# fallback moves every chain shorter or longer so the whole swing clears the
	# band a bird holding its height sweeps. So no height is skipped any more.
	var swing := RoomDef.new("swing", "mid", 30)
	var big: Array[Callable] = [_big_lantern]
	var twin: Array[Callable] = [_twin_lanterns]
	var chimes: Array[Callable] = [_chime.bind(0), _chime.bind(1), _chime.bind(2)]
	var gusty: Array[Callable] = [_gusty_lantern]
	var winch: Array[Callable] = [_winch_lantern]
	swing.variants = [
		RoomVariant.new("big").generated(_gen_swing.bind(big)),
		RoomVariant.new("twin").generated(_gen_swing.bind(twin)),
		RoomVariant.new("chimes").generated(_gen_swing.bind(chimes)),
		RoomVariant.new("gusty").generated(_gen_swing.bind(gusty)),
		RoomVariant.new("winch").generated(_gen_swing.bind(winch)),
	]
	out.append(swing)

	# Stalker Rail: a spike pair on the far wall slides toward the bird's height.
	var stalker := RoomDef.new("stalker", "mid", 40)
	stalker.max_spikes = 6
	stalker.hazards.append(func() -> Hazard: return Stalker.new())
	out.append(stalker)

	# Pinwheel: a pinwheel turns in the middle of the room. Variants: the plain
	# wheel, three blades, a twin pair, one that rocks back and forth, one off
	# to one side, one whose blades grow and shrink.
	var pinwheel := RoomDef.new("pinwheel", "mid", 40)
	# Every variant is GENERATED (_gen_pinwheel): out of a portal the wheel sits
	# clear of the band a bird holding its height anywhere in the exit sweeps.
	for shape: String in PINWHEELS:
		pinwheel.variants.append(RoomVariant.new(shape).generated(_gen_pinwheel.bind(shape)))
	out.append(pinwheel)

	# Saw Ring: saws circle the middle; the ring grows and shrinks on a beat.
	# Variants: the classic ring, a small ring turning the other way inside a
	# big one, a ring left of the middle, a flat oval, and two faster saws.
	# Every saw stays inside x 70..290 px.
	var sawring := RoomDef.new("sawring", "late", 80)
	sawring.weight = 8
	sawring.max_spikes = 6
	for shape: String in SAW_RINGS:
		sawring.variants.append(RoomVariant.new(shape).with([_saw_ring.bind(shape)]))
	out.append(sawring)

	return out


## Generated Pinwheel: the variant's wheel as hand made (it draws its start
## angle and way round), moved clear of the hold band (Rotor.place_for_arrival).
## The fallback is a fixed search, no draws: the first of the wheel's
## fallback_spots x GENERATE_SPINS starting angles that passes VariantCheck,
## else the last one tried.
static func _gen_pinwheel(p: VariantParams, shape: String) -> void:
	var r: Hazard = p.add(_pinwheel(shape))
	r.place_for_arrival(p)
	if not p.fallback or not p.arriving:
		return
	for cy: int in r.fallback_spots(p):
		for k in Rotor.GENERATE_SPINS:
			r.center_y = cy
			r.phase = Rotor.fallback_angle(k)
			r._place()
			if VariantCheck.holds(p.sim):
				return


## One Pinwheel variant. Most use the trimmed wheel (blades 64 px, 14 wide,
## hub 14); the original Rotor.new() is 80 / 16 / 16.
static func _pinwheel(shape: String) -> Hazard:
	match shape:
		"twin":
			var pair := Rotor.new(42 * SUB, 6 * SUB, 11 * SUB)
			pair.hubs = 2
			pair.spread_x = 60 * SUB
			pair.spread_y = 72 * SUB
			pair.period = 300
			return pair
		"lean":
			var side := Rotor.new(52 * SUB, 6 * SUB, 12 * SUB)
			side.lean = 52 * SUB
			return side
		"breathe":
			var lung := Rotor.new(72 * SUB, 7 * SUB, 14 * SUB)
			lung.spin = Rotor.Spin.BREATHE
			lung.blade_min = 40 * SUB
			return lung
	var r := Rotor.new(64 * SUB, 7 * SUB, 14 * SUB)
	if shape == "three":
		r.blades = 3
	elif shape == "rock":
		r.spin = Rotor.Spin.ROCK
	return r


## One Saw Ring variant. "classic" is SawRing.new() as is.
static func _saw_ring(shape: String) -> Hazard:
	var ring := SawRing.new()
	match shape:
		"two-rings":
			# Three big saws outside, two small ones inside turning back.
			ring.fixed_count = 3
			ring.ring_min = 60 * SUB
			ring.inner_count = 2
			ring.inner_min = 20 * SUB
			ring.inner_max = 34 * SUB
			ring.inner_saw = 13 * SUB
		"off-centre":
			# Three saws round a point 44 px left of the middle.
			ring.fixed_count = 3
			ring.center_x = 136 * SUB
			ring.ring_min = 28 * SUB
			ring.ring_max = 48 * SUB
		"oval":
			# Four saws on an orbit half as tall as it is wide.
			ring.fixed_count = 4
			ring.ry_num = 1
			ring.ry_den = 2
		"pair":
			# Two saws opposite each other, a lap in 3 s instead of 5 s.
			ring.fixed_count = 2
			ring.period = 180
	return ring


## Caterpillar Crawl's variants (Summer Crab Walk has the same): two crawlers,
## one starting on the ceiling and one on the floor; a swarm of four small ones,
## two on each; two short ones at double speed.
static func crawl_variants() -> Array[RoomVariant]:
	return [
		RoomVariant.new("classic").generated(_gen_crawl.bind("classic")),
		RoomVariant.new("swarm").generated(_gen_crawl.bind("swarm")),
		RoomVariant.new("sprinters").generated(_gen_crawl.bind("sprinters")),
	]


## Generated Caterpillar Crawl: the variant's crawlers as hand made (each draws
## its start). The fallback puts every crawler on the edge away from the bird
## (the floor for an arrival in the upper half, else the ceiling), each the same
## way along it.
static func _gen_crawl(p: VariantParams, shape: String) -> void:
	var made: Array[Hazard] = []
	match shape:
		"swarm":
			made.append(p.add(_swarm(0, false)))
			made.append(p.add(_swarm(0, true)))
			made.append(p.add(_swarm(1, false)))
			made.append(p.add(_swarm(1, true)))
		"sprinters":
			made.append(p.add(_sprinter(0)))
			made.append(p.add(_sprinter(1)))
		_:
			made.append(p.add(_crawler(0)))
			made.append(p.add(_crawler(1)))
	if not p.fallback or not p.arriving:
		return
	# Lane 0 starts on the ceiling, lane 1 on the floor: move the ones on the
	# bird's side half way round the path, onto the other edge.
	var away := 1 if p.entry_y < SimConfig.WORLD_H / 2 else 0
	for h in made:
		if h.lane != away:
			h.start = posmod(h.start + Crawler.W + Crawler.H, Crawler.PERIMETER)
			h._place()


## Generated Shutter Gates: the classic pair (the second GEN_LAG behind the
## first, the first on the side the bird comes in) or one faster gate in the
## middle, all wide (Gate.wide), timed for the arrival once they are set up
## (Gate.fit_arrival). A try only differs in the leader's drawn direction; the
## timing search covers every phase.
static func _gen_gates(p: VariantParams, single: bool) -> void:
	var made: Array[Hazard] = []
	if single:
		made.append(p.add(Gate.new(180 * SUB, SINGLE_PERIOD, false).wide()))
	else:
		var flip := p.arriving and p.sim.state.vx < 0
		made.append(p.add(Gate.new((230 if flip else 130) * SUB, 760, false).wide()))
		made.append(p.add(Gate.new((130 if flip else 230) * SUB, 760, true).wide()))
	Gate.fit_arrival(p.sim, p, made)


static func _crawler(lane: int) -> Hazard:
	return Crawler.new(lane)


static func _swarm(lane: int, trails: bool) -> Hazard:
	return Crawler.new(lane).trailing() if trails else Crawler.new(lane).swarm()


static func _sprinter(lane: int) -> Hazard:
	return Crawler.new(lane).sprinter()


## Generated Lantern Swing: the lanterns as hand made (each draws its swing
## and times it to the arrival path). The fallback is a fixed search, no draws:
## each lantern moves to the nearest chain that keeps its whole swing off the
## hold band (Pendulum.fit_clear); if that is not enough (VariantCheck), the
## hand-made lanterns at FALLBACK_PHASES swing phases.
static func _gen_swing(p: VariantParams, factories: Array[Callable]) -> void:
	var made := p.add_all(factories)
	if not p.fallback or not p.arriving:
		return
	for h in made:
		h.fit_clear(p)
	if VariantCheck.holds(p.sim):
		return
	for k in Pendulum.FALLBACK_PHASES:
		for h in made:
			h.phase = k * SimTrig.TURN / Pendulum.FALLBACK_PHASES
			h._place()
		if VariantCheck.holds(p.sim):
			return


## Lantern Swing, big: a 330 px chain, a 28 px lantern, about 20 degrees each
## way, 3.5 s a swing.
static func _big_lantern() -> Hazard:
	return Pendulum.new(180 * SUB, 330 * SUB, 28 * SUB, 56, 210)


## Lantern Swing, twin: a short and a long chain swinging opposite ways; they
## cross at heights 90 px apart.
static func _twin_lanterns() -> Hazard:
	return Pendulum.new(130 * SUB, 200 * SUB, 20 * SUB, 45, 180).with_twin(218 * SUB, 290 * SUB)


## Lantern Swing, chimes: three small lanterns, each with its own swing time
## (2.5 s, 3 s, 3.5 s), so the pattern keeps changing.
static func _chime(i: int) -> Hazard:
	var xs: Array[int] = [95, 180, 265]
	var lengths: Array[int] = [150, 240, 150]
	var periods: Array[int] = [150, 180, 210]
	return Pendulum.new(xs[i] * SUB, lengths[i] * SUB, 15 * SUB, 40, periods[i])


## Lantern Swing, gusty: the widest swing grows from about 8 to 21 degrees and
## back every 10 s.
static func _gusty_lantern() -> Hazard:
	return Pendulum.new(180 * SUB, 300 * SUB, 24 * SUB, 41, 180).gusting(18, 600)


## Lantern Swing, winch: the chain winds between 200 and 330 px every 7 s.
static func _winch_lantern() -> Hazard:
	return Pendulum.new(180 * SUB, 265 * SUB, 24 * SUB, 50, 180).winding(65 * SUB, 420)
