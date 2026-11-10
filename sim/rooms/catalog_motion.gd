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
	# Near the top and bottom the gaps are at the end of their range and turn
	# away before a slow player gets through both gates.
	gates.arrival_skip = PackedInt32Array([0, 178 * SUB, 502 * SUB, SimConfig.WORLD_H])
	gates.hazards.append(_gate.bind(130 * SUB, 760, false))
	gates.hazards.append(_gate.bind(230 * SUB, 760, true))
	out.append(gates)

	# Caterpillar Crawl: crawlers walk round the inside of the cage.
	var crawl := RoomDef.new("crawl", "starter", 30)
	# A crawler walks the ceiling.
	crawl.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	crawl.variants = crawl_variants()
	out.append(crawl)

	# Lantern Swing: lanterns on chains swing from the ceiling. Variants: one
	# big lantern; twins swinging opposite ways; a row of three small ones on
	# their own beats; a gusty swing that grows and shrinks; a winch that winds
	# the chain up and down. Every lantern stays inside x 40..320 px (clear of
	# a bird at either wall) and moves slower than the bird.
	# Each variant skips the portal heights where a bird holding height meets a
	# lantern at the bottom of its swing however it is timed
	# (tests/unit/test_arrival_check.gd); some variant fits every height.
	var swing := RoomDef.new("swing", "mid", 30)
	swing.variants = [
		RoomVariant.new("big").with([_big_lantern]).skipping(_px_range(362, 428)),
		RoomVariant.new("twin").with([_twin_lanterns]).skipping(_px_range(226, 380)),
		RoomVariant.new("chimes").with([_chime.bind(0), _chime.bind(1), _chime.bind(2)]).skipping(
			_px_range(192, 324)
		),
		RoomVariant.new("gusty").with([_gusty_lantern]).skipping(_px_range(336, 392)),
		RoomVariant.new("winch").with([_winch_lantern]).skipping(_px_range(240, 310)),
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
	for shape: String in PINWHEELS:
		pinwheel.variants.append(RoomVariant.new(shape).with([_pinwheel.bind(shape)]))
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


static func _gate(x: int, period: int, follows: bool) -> Hazard:
	return Gate.new(x, period, follows)


## Caterpillar Crawl's variants (Summer Crab Walk has the same): two crawlers,
## one starting on the ceiling and one on the floor; a swarm of four small ones,
## two on each; two short ones at double speed.
static func crawl_variants() -> Array[RoomVariant]:
	return [
		RoomVariant.new("classic").with([_crawler.bind(0), _crawler.bind(1)]),
		RoomVariant.new("swarm").with(
			[
				_swarm.bind(0, false),
				_swarm.bind(0, true),
				_swarm.bind(1, false),
				_swarm.bind(1, true)
			]
		),
		RoomVariant.new("sprinters").with([_sprinter.bind(0), _sprinter.bind(1)]),
	]


static func _crawler(lane: int) -> Hazard:
	return Crawler.new(lane)


static func _swarm(lane: int, trails: bool) -> Hazard:
	return Crawler.new(lane).trailing() if trails else Crawler.new(lane).swarm()


static func _sprinter(lane: int) -> Hazard:
	return Crawler.new(lane).sprinter()


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


## A from-to range of heights in pixels, as sub-units.
static func _px_range(from_px: int, to_px: int) -> PackedInt32Array:
	return PackedInt32Array([from_px * SUB, to_px * SUB])
