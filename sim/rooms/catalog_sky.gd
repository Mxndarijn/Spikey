extends RefCounted
## Rooms batch: sky and bonus rooms (air, bubbles and things that fall from the
## ceiling). Order is part of the rules (see RoomCatalog).
## Also home to two hazards used by seasonal rooms: mover.gd (Bat Loop, Bee
## Line) and firework.gd (Firework Burst).

const Updraft := preload("res://sim/hazards/updraft.gd")
const Bubble := preload("res://sim/hazards/bubble.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const OrchardSpawner := preload("res://sim/hazards/orchard_spawner.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Updraft: the middle lane pushes the bird up.
	var updraft := RoomDef.new("updraft", "mid", 60)
	updraft.hazards.append(func() -> Hazard: return Updraft.new())
	out.append(updraft)

	# Bubble Lift: rising bubbles carry the bird until a tap pops them.
	var bubbles := RoomDef.new("bubbles", "mid", 50)
	# A bubble can carry the bird up into the ceiling.
	bubbles.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	for lane in 3:
		bubbles.hazards.append(_bubble.bind(lane))
	out.append(bubbles)

	# Spike Rain: a mark on the ceiling, then a spiked drop falls down that column.
	# Variants, one drawn each time the room starts: Classic (as it was), Drizzle
	# (slow, long warning), Hail (four small drops), Sweep (four fixed columns in
	# turn, then back), Shatter (shards skip along the floor), Wobble (drops sway)
	# and Stake (a floor spike grows where a heavy drop lands).
	var rain := RoomDef.new("rain", "late", 70)
	rain.weight = 8
	var hail: Array[Callable] = []
	for d in [30, 55, 80, 105]:
		hail.append(_rain.bind(d, 10 * SUB, 45, Drop.WARN, 6 * SUB, Drop.Style.PLAIN))
	var sweep: Array[Callable] = []
	for i in 4:
		sweep.append(_sweep.bind(30 + 12 * i, (45 + 90 * i) * SUB))
	rain.variants = [
		RoomVariant.new("classic").with(
			[_drop.bind(30, 10 * SUB, 25), _drop.bind(70, 10 * SUB, 25)]
		),
		(
			RoomVariant
			. new("drizzle")
			. with(
				[
					_rain.bind(30, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
					_rain.bind(135, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
				]
			)
		),
		RoomVariant.new("hail").with(hail),
		RoomVariant.new("sweep").with(sweep),
		(
			RoomVariant
			. new("shatter")
			. with(
				[
					_rain.bind(30, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
					_rain.bind(85, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
				]
			)
		),
		(
			RoomVariant
			. new("wobble")
			. with(
				[
					_rain.bind(30, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
					_rain.bind(90, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
				]
			)
		),
		(
			RoomVariant
			. new("stake")
			. with(
				[
					_rain.bind(30, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
					_rain.bind(140, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
				]
			)
		),
	]
	out.append(rain)

	# Orchard Drop: coins fall in columns, now and then a thorny pinecone too.
	var orchard := RoomDef.new("orchard", "bonus", 30)
	orchard.weight = 4
	orchard.max_spikes = 2
	orchard.bounce_coin = false
	orchard.hazards.append(func() -> Hazard: return OrchardSpawner.new())
	orchard.hazards.append(_drop.bind(90, 6 * SUB, 140))
	out.append(orchard)

	# Keepy-Uppy: bump the soft ball to keep it up; every bump pays a coin.
	var keepy := RoomDef.new("keepy", "bonus", 40)
	keepy.weight = 4
	keepy.max_spikes = 3
	keepy.hazards.append(func() -> Hazard: return KeepyBall.new())
	out.append(keepy)

	return out


static func _bubble(lane: int) -> Hazard:
	return Bubble.new(lane)


static func _drop(delay: int, speed: int, gap: int) -> Hazard:
	return Drop.new(delay, speed, gap)


static func _rain(
	delay: int, speed: int, gap: int, warn: int, radius: int, style: Drop.Style
) -> Hazard:
	return Drop.new(delay, speed, gap, warn, radius, style)


## Sweep: a fixed column, at today's speed and warning.
static func _sweep(delay: int, column: int) -> Hazard:
	return Drop.new(delay, 10 * SUB, 60, Drop.WARN, Drop.RADIUS, Drop.Style.PLAIN, column)
