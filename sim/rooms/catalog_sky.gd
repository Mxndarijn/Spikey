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
## Spiky Bubbles: steps between the two spiked bubbles' first rises (about
## half a rise apart).
const SPIKY_SPREAD := 230


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
	# Out of a portal high up, the hover lanes are skipped: a tap to hold height
	# in one keeps rising (hover cancels gravity) into the ceiling.
	var high := PackedInt32Array([0, 172 * SUB])
	updraft.variants = [
		RoomVariant.new("chimney").with([_air.bind(180, 50, Updraft.CHIMNEY)]),
		(
			RoomVariant
			. new("twin")
			. with([_air.bind(100, 40, Updraft.HOVER), _air.bind(260, 40, Updraft.HOVER)])
			. skipping(high)
		),
		RoomVariant.new("drift").with([_drift.bind(70, 220, 50)]),
		RoomVariant.new("gust").with([_gust]),
		(
			RoomVariant
			. new("updown")
			. with([_air.bind(120, 50, Updraft.HOVER), _air.bind(240, 50, -Updraft.HOVER)])
			. skipping(high)
		),
		RoomVariant.new("coins").with(coins),
	]
	out.append(updraft)

	# Bubble Lift: rising bubbles carry the bird until a tap pops them.
	# Variants: classic (three bubbles); giants (three big, slow ones); spiky
	# (two safe bubbles and two spiked ones, each marked on the floor for a
	# second before it rises); coin-bubbles (a coin in every other bubble).
	var bubbles := RoomDef.new("bubbles", "mid", 50)
	# A bubble can carry the bird up into the ceiling.
	bubbles.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	var classic: Array[Callable] = []
	var giants: Array[Callable] = []
	var coin_bubbles: Array[Callable] = []
	for lane in 3:
		classic.append(_bubble.bind(lane))
		giants.append(_giant.bind(lane))
		coin_bubbles.append(_coin_bubble.bind(lane) if lane % 2 == 0 else _bubble.bind(lane))
	bubbles.variants = [
		RoomVariant.new("classic").with(classic),
		RoomVariant.new("giants").with(giants),
		(
			RoomVariant
			. new("spiky")
			. with(
				[
					_bubble.bind(0),
					_spiky_bubble.bind(1, 0),
					_bubble.bind(2),
					_spiky_bubble.bind(3, SPIKY_SPREAD),
				]
			)
		),
		RoomVariant.new("coin-bubbles").with(coin_bubbles),
	]
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
	# Variants: one ball; two balls to keep up at once.
	keepy.variants = [
		RoomVariant.new("classic").with([func() -> Hazard: return KeepyBall.new()]),
		RoomVariant.new("two-balls").with(
			[
				func() -> Hazard: return KeepyBall.new().dropping(0),
				func() -> Hazard: return KeepyBall.new().dropping(KeepyBall.SECOND_DROP),
			]
		),
	]
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


static func _giant(lane: int) -> Hazard:
	return Bubble.new(lane, Bubble.GIANT_RADIUS, Bubble.GIANT_RISE)


static func _spiky_bubble(lane: int, delay: int) -> Hazard:
	return Bubble.new(lane).spiky(delay)


static func _coin_bubble(lane: int) -> Hazard:
	return Bubble.new(lane).with_coin()


static func _drop(delay: int, speed: int, gap: int) -> Hazard:
	return Drop.new(delay, speed, gap)


static func _rain(
	delay: int, speed: int, gap: int, warn: int, radius: int, style: Drop.Style
) -> Hazard:
	return Drop.new(delay, speed, gap, warn, radius, style)


## Sweep: a fixed column, at today's speed and warning.
static func _sweep(delay: int, column: int) -> Hazard:
	return Drop.new(delay, 10 * SUB, 60, Drop.WARN, Drop.RADIUS, Drop.Style.PLAIN, column)
