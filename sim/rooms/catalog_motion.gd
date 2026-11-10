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

	# Caterpillar Crawl: two crawlers walk round the inside of the cage.
	var crawl := RoomDef.new("crawl", "starter", 30)
	# A crawler walks the ceiling.
	crawl.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	crawl.hazards.append(_crawler.bind(0))
	crawl.hazards.append(_crawler.bind(1))
	out.append(crawl)

	# Lantern Swing: a lantern on a chain swings through the middle.
	var swing := RoomDef.new("swing", "mid", 30)
	swing.hazards.append(func() -> Hazard: return Pendulum.new())
	# Held there, the bird meets the lantern at the bottom of its swing.
	swing.arrival_skip = PackedInt32Array([318 * SUB, 368 * SUB])
	out.append(swing)

	# Stalker Rail: a spike pair on the far wall slides toward the bird's height.
	var stalker := RoomDef.new("stalker", "mid", 40)
	stalker.max_spikes = 6
	stalker.hazards.append(func() -> Hazard: return Stalker.new())
	out.append(stalker)

	# Pinwheel: a four-blade pinwheel turns in the middle of the room.
	var pinwheel := RoomDef.new("pinwheel", "mid", 40)
	pinwheel.hazards.append(func() -> Hazard: return Rotor.new())
	out.append(pinwheel)

	# Saw Ring: saws circle the middle; the ring grows and shrinks on a beat.
	var sawring := RoomDef.new("sawring", "late", 80)
	sawring.weight = 8
	sawring.max_spikes = 6
	sawring.hazards.append(func() -> Hazard: return SawRing.new())
	out.append(sawring)

	return out


static func _gate(x: int, period: int, follows: bool) -> Hazard:
	return Gate.new(x, period, follows)


static func _crawler(lane: int) -> Hazard:
	return Crawler.new(lane)
