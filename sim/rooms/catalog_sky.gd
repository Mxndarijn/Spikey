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
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Updraft: columns of moving air. Each variant gives the air a job:
	# - chimney: 1.5 gravity in a 100 px middle band, carries a fresh flap up
	#   to the ceiling (enter falling);
	# - twin: two hover lanes near the walls (line up early, then coast);
	# - drift: a hover lane sliding wall to wall;
	# - gust: the middle column blows at twice gravity after a 1 s warning;
	# - updown: a hover lane beside a downdraft (flap through the sink);
	# - coins: today's soft column with three coins up its middle.
	var updraft := RoomDef.new("updraft", "mid", 60)
	var coins: Array[Callable] = [_air.bind(180, 60, Updraft.LIFT)]
	for y_px: int in [220, 270, 320]:
		coins.append(_coin.bind(180, y_px))
	updraft.variants = [
		RoomVariant.new("chimney").with([_air.bind(180, 50, Updraft.CHIMNEY)]),
		RoomVariant.new("twin").with(
			[_air.bind(100, 40, Updraft.HOVER), _air.bind(260, 40, Updraft.HOVER)]
		),
		RoomVariant.new("drift").with([_drift.bind(70, 220, 50)]),
		RoomVariant.new("gust").with([_gust]),
		RoomVariant.new("updown").with(
			[_air.bind(120, 50, Updraft.HOVER), _air.bind(240, 50, -Updraft.HOVER)]
		),
		RoomVariant.new("coins").with(coins),
	]
	out.append(updraft)

	# Bubble Lift: rising bubbles carry the bird until a tap pops them.
	var bubbles := RoomDef.new("bubbles", "mid", 50)
	# A bubble can carry the bird up into the ceiling.
	bubbles.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	for lane in 3:
		bubbles.hazards.append(_bubble.bind(lane))
	out.append(bubbles)

	# Spike Rain: a mark on the ceiling, then a spiked drop falls down that column.
	var rain := RoomDef.new("rain", "late", 70)
	rain.weight = 8
	rain.hazards.append(_drop.bind(30, 10 * SUB, 25))
	rain.hazards.append(_drop.bind(70, 10 * SUB, 25))
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


## An air column centered at `x_px`, `half_px` wide each side, `lift` per step.
static func _air(x_px: int, half_px: int, lift: int) -> Hazard:
	return Updraft.new(x_px * SUB, half_px * SUB, lift)


## A hover column whose center drifts between `min_px` and `min_px + span_px`.
static func _drift(min_px: int, span_px: int, half_px: int) -> Hazard:
	return Updraft.new(min_px * SUB, half_px * SUB, Updraft.HOVER).drifting(
		min_px * SUB, span_px * SUB
	)


## The middle column, blowing at twice gravity in gusts.
static func _gust() -> Hazard:
	return Updraft.new(SimConfig.WORLD_W / 2, Updraft.HALF_W, Updraft.STRONG).gusty()


static func _coin(x_px: int, y_px: int) -> Hazard:
	return CoinPickup.new(x_px * SUB, y_px * SUB)


static func _bubble(lane: int) -> Hazard:
	return Bubble.new(lane)


static func _drop(delay: int, speed: int, gap: int) -> Hazard:
	return Drop.new(delay, speed, gap)
