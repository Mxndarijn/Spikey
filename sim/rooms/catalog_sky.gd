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
	# Every variant is GENERATED (_gen_updraft): out of a portal the chimney's
	# and the coin column's place is drawn until a bird holding its height is
	# not carried into the ceiling (or, by a downdraft, the floor), and the safe
	# fallback stops the air short of the bird's band: rising air starts below
	# it, falling air stops above it. So no height is skipped any more.
	updraft.variants = []
	for shape: String in ["chimney", "twin", "drift", "gust", "updown", "coins"]:
		updraft.variants.append(RoomVariant.new(shape).generated(_gen_updraft.bind(shape)))
	out.append(updraft)

	# Bubble Lift: rising bubbles carry the bird until a tap pops them.
	# Variants: classic (three bubbles); giants (three big, slow ones); spiky
	# (two safe bubbles and two spiked ones, each marked on the floor for a
	# second before it rises); coin-bubbles (a coin in every other bubble).
	# Every variant is GENERATED: a bubble could carry a bird out of a high
	# portal up into the ceiling, so out of a portal the bubbles' columns are
	# drawn again until none touches a bird holding its height (_gen_bubbles).
	var bubbles := RoomDef.new("bubbles", "mid", 50)
	var classic: Array[Callable] = []
	var giants: Array[Callable] = []
	var coin_bubbles: Array[Callable] = []
	for lane in 3:
		classic.append(_bubble.bind(lane))
		giants.append(_giant.bind(lane))
		coin_bubbles.append(_coin_bubble.bind(lane) if lane % 2 == 0 else _bubble.bind(lane))
	var spiky: Array[Callable] = [
		_bubble.bind(0),
		_spiky_bubble.bind(1, 0),
		_bubble.bind(2),
		_spiky_bubble.bind(3, SPIKY_SPREAD),
	]
	bubbles.variants = [
		RoomVariant.new("classic").generated(_gen_bubbles.bind(classic), true),
		RoomVariant.new("giants").generated(_gen_bubbles.bind(giants), true),
		RoomVariant.new("spiky").generated(_gen_bubbles.bind(spiky), true),
		RoomVariant.new("coin-bubbles").generated(_gen_bubbles.bind(coin_bubbles), true),
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
	var classic_rain: Array[Callable] = [_drop.bind(30, 10 * SUB, 25), _drop.bind(70, 10 * SUB, 25)]
	var drizzle: Array[Callable] = [
		_rain.bind(30, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
		_rain.bind(135, 6 * SUB, 30, 75, Drop.RADIUS, Drop.Style.PLAIN),
	]
	var shatter: Array[Callable] = [
		_rain.bind(30, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
		_rain.bind(85, 10 * SUB, 40, 50, Drop.RADIUS, Drop.Style.SHATTER),
	]
	var wobble: Array[Callable] = [
		_rain.bind(30, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
		_rain.bind(90, 7 * SUB, 30, 55, Drop.RADIUS, Drop.Style.WOBBLE),
	]
	var stake: Array[Callable] = [
		_rain.bind(30, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
		_rain.bind(140, 8 * SUB, 30, 60, 13 * SUB, Drop.Style.STAKE),
	]
	# Every variant is GENERATED (_gen_rain), checked over the arrival path's
	# length (the first drop falls after the reading time).
	var hold := FairLanes.ARRIVAL_PATH_TICKS
	rain.variants = [
		RoomVariant.new("classic").generated(_gen_rain.bind(classic_rain, false), false, hold),
		RoomVariant.new("drizzle").generated(_gen_rain.bind(drizzle, false), false, hold),
		RoomVariant.new("hail").generated(_gen_rain.bind(hail, false), false, hold),
		RoomVariant.new("sweep").generated(_gen_rain.bind(sweep, true), false, hold),
		RoomVariant.new("shatter").generated(_gen_rain.bind(shatter, false), false, hold),
		RoomVariant.new("wobble").generated(_gen_rain.bind(wobble, false), false, hold),
		RoomVariant.new("stake").generated(_gen_rain.bind(stake, false), false, hold),
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
## Generated Updraft. Out of a portal a gust starts at the top of its rest,
## so the first gust comes 2 s in, after its warning. The columns keep their
## hand-made places (moving the chimney or the coin column sideways was
## measured: more early deaths, at the first wall bounce) and their own draws
## (drift). The fallback cuts every column short of the hold band
## (Updraft.clear_band).
static func _gen_updraft(p: VariantParams, shape: String) -> void:
	var cx := 180
	var made: Array[Hazard] = []
	match shape:
		"chimney":
			made.append(p.add(_air(cx, 50, Updraft.CHIMNEY)))
		"twin":
			made.append(p.add(_air(100, 40, Updraft.HOVER)))
			made.append(p.add(_air(260, 40, Updraft.HOVER)))
		"drift":
			made.append(p.add(_drift(70, 220, 50)))
		"gust":
			var g: Hazard = p.add(_gust())
			if p.arriving:
				g.phase = 0
				g._update()
			made.append(g)
		"updown":
			made.append(p.add(_air(120, 50, Updraft.HOVER)))
			made.append(p.add(_air(240, 50, -Updraft.HOVER)))
		_:
			made.append(p.add(_air(cx, 60, Updraft.LIFT)))
			for y_px: int in [220, 270, 320]:
				p.add(_coin(cx, y_px))
	# Out of a portal the up-down pair always stops short of the band (a
	# downdraft would pull a bird holding its height down), the rest only on
	# the fallback.
	if p.arriving and (p.fallback or shape == "updown"):
		for h in made:
			h.clear_band(p)


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


## Generated Bubble Lift: the variant's bubbles as hand made (each draws its
## columns). The fallback starts every bubble under the floor, as a spiked one
## does: none can reach a bird out of a portal while it reads the room.
static func _gen_bubbles(p: VariantParams, factories: Array[Callable]) -> void:
	var made := p.add_all(factories)
	if not p.fallback or not p.arriving:
		return
	for b in made:
		if not b.spiked:
			b.y = SimConfig.WORLD_H + b.radius


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
## Generated Spike Rain: the drops as hand made (each draws its columns). Out
## of a portal the sweep draws which end it starts from (its fixed columns, or
## mirrored). The fallback starts every drop the arrival path's length later,
## its column marked as usual when its turn comes.
static func _gen_rain(p: VariantParams, factories: Array[Callable], sweep: bool) -> void:
	var flip := false
	if sweep and p.arriving and not p.fallback:
		flip = p.rng.next_below(2) == 1
	var made := p.add_all(factories)
	for d in made:
		if flip:
			d.column = SimConfig.WORLD_W - d.column
		if p.fallback and p.arriving:
			d.timer += FairLanes.ARRIVAL_PATH_TICKS


static func _sweep(delay: int, column: int) -> Hazard:
	return Drop.new(delay, 10 * SUB, 60, Drop.WARN, Drop.RADIUS, Drop.Style.PLAIN, column)
