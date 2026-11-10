extends RefCounted
## Core rooms: the basic cage and its variants, plus the rooms that change the
## walls, gravity or speed. Order is part of the rules (see RoomCatalog).

const Block := preload("res://sim/hazards/block.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const SplittingBouncer := preload("res://sim/hazards/splitting_bouncer.gd")
const RevvingBouncer := preload("res://sim/hazards/revving_bouncer.gd")
const CuriousBouncer := preload("res://sim/hazards/curious_bouncer.gd")
const HeavyBouncer := preload("res://sim/hazards/heavy_bouncer.gd")
const OrbitCoin := preload("res://sim/hazards/orbit_coin.gd")
const SpikeBall := preload("res://sim/hazards/spike_ball.gd")

const SUB := SimConfig.SUB
## Coin Garden: the middle of the coin diamond, and how far out Orbiting Coins
## circle it.
const GARDEN_CX := 180 * SUB
const GARDEN_CY := 320 * SUB
const ORBIT_RADIUS := 95 * SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Open Sky: the classic cage, where every run starts.
	out.append(RoomDef.new("open", "starter", 0))

	# Crowded: Open Sky with a spike more per wall. Variants: as is; Lopsided
	# (two more on the left wall, two fewer on the right); Spike storm (two
	# more on each wall).
	var crowded := RoomDef.new("crowded", "starter", 10)
	crowded.extra_spikes = 1
	crowded.variants = [
		RoomVariant.new("classic"),
		RoomVariant.new("lopsided").leaning(2),
		RoomVariant.new("storm").sized(1, 1, 2),
	]
	out.append(crowded)

	# Narrow: both walls slide 50 px in, so every crossing is short. The free
	# run and the exit stay near the bird: there is no time to cross the whole
	# height in one trip.
	var narrow := RoomDef.new("narrow", "starter", 10)
	narrow.inset = 50 * SUB
	narrow.reach = 100 * SUB
	out.append(narrow)

	# Tide Spikes: some wall spikes slide in and out on a slow beat. Variants:
	# normal; fewer but big spikes (1.5 times); more but small ones (2/3).
	var tide := RoomDef.new("tide", "starter", 10)
	tide.wall_mode = RoomDef.WallMode.TIDE
	tide.variants = [
		RoomVariant.new("normal"),
		RoomVariant.new("big").sized(3, 2, -1),
		RoomVariant.new("small").sized(2, 3, 3),
	]
	out.append(tide)

	# Floating Isles: four still islands, one per band of the room. Variants:
	# still; drifting (they sway sideways together on a slow loop); one big
	# rock across the middle.
	var isles := RoomDef.new("isles", "starter", 10)
	isles.max_spikes = 6
	isles.variants = [
		RoomVariant.new("classic").with(islands(0)),
		RoomVariant.new("drifting").with(islands(Block.DRIFT)),
		RoomVariant.new("one-big").with([_big_rock]),
	]
	out.append(isles)

	# Coin Garden: a breather with up to three spikes per wall and four coins.
	# Every bounce adds a coin, even when one is already out. Variants: classic
	# (a still diamond of coins); orbit (the diamond slowly turns); decoy (one
	# of the four spots holds a spiked ball instead of a coin).
	var garden := RoomDef.new("garden", "bonus", 20)
	garden.weight = 4
	garden.max_spikes = 3
	garden.bounce_coin_stacks = true
	# A diamond of coins: [x, y] in pixels.
	var diamond := [[180, 220], [120, 320], [240, 320], [180, 420]]
	var still: Array[Callable] = []
	var spots := PackedInt32Array()
	for p: Array in diamond:
		still.append(_coin.bind(int(p[0]) * SUB, int(p[1]) * SUB, 0))
		spots.append(int(p[0]) * SUB)
		spots.append(int(p[1]) * SUB)
	var orbit: Array[Callable] = []
	for i in 4:
		orbit.append(_orbit_coin.bind(i * SimTrig.TURN / 4))
	var decoy: Array[Callable] = still.duplicate()
	decoy.append(_decoy.bind(spots))
	garden.variants = [
		RoomVariant.new("classic").with(still),
		RoomVariant.new("orbit").with(orbit),
		RoomVariant.new("decoy").with(decoy),
	]
	out.append(garden)

	# Bramble Ball: a spiked ball bouncing around the room. Variants: the
	# classic ball; two smaller ones in the upper and lower lanes; one that
	# splits in two; one that speeds up per bounce; one that steers toward the
	# bird's height; a heavy one that bounces off the floor in arcs.
	var bramble := RoomDef.new("bramble", "mid", 40)
	bramble.variants = [
		RoomVariant.new("classic").with([func() -> Hazard: return Bouncer.new()]),
		RoomVariant.new("twin").with(
			[_twin.bind(Bouncer.Lane.UPPER), _twin.bind(Bouncer.Lane.LOWER)]
		),
		RoomVariant.new("split").with([func() -> Hazard: return SplittingBouncer.new()]),
		RoomVariant.new("revup").with([func() -> Hazard: return RevvingBouncer.new()]),
		RoomVariant.new("curious").with([func() -> Hazard: return CuriousBouncer.new()]),
		RoomVariant.new("heavy").with([func() -> Hazard: return HeavyBouncer.new()]),
	]
	out.append(bramble)

	# Squeeze Box: every point here moves both walls in a step. Variants: as
	# is; Left press (only the left wall, in bigger steps); Breathing box (the
	# walls slide in and back out on a loop).
	var squeeze := RoomDef.new("squeeze", "mid", 50)
	squeeze.squeeze = true
	squeeze.variants = [
		RoomVariant.new("classic"),
		RoomVariant.new("left-only").squeezing(RoomVariant.Squeeze.LEFT),
		RoomVariant.new("breathing").squeezing(RoomVariant.Squeeze.BREATHE),
	]
	out.append(squeeze)

	# Slow-Mo Breather: everything at half speed, an arc of coins, few spikes.
	var slowmo := RoomDef.new("slowmo", "bonus", 60)
	slowmo.weight = 4
	slowmo.speed = RoomDef.Speed.SLOW
	slowmo.max_spikes = 2
	# Variants: classic (the arc) and zigzag (five coins high, low, high...).
	var arc: Array[int] = [0, 60, 80, 60, 0]
	var arc_coins: Array[Callable] = []
	var zigzag: Array[Callable] = []
	for i in 5:
		var x := (90 + i * 45) * SUB
		arc_coins.append(_coin.bind(x, (330 - arc[i]) * SUB, 0))
		zigzag.append(_coin.bind(x, (380 if i % 2 == 1 else 280) * SUB, 0))
	slowmo.variants = [
		RoomVariant.new("classic").with(arc_coins),
		RoomVariant.new("zigzag").with(zigzag),
	]
	out.append(slowmo)

	# Blink Walls: each wall flips between two spike patterns every second.
	# Variants: as is; Fast blink (twice a second, with a free run both
	# patterns share).
	var blink := RoomDef.new("blink", "late", 80)
	blink.weight = 8
	blink.wall_mode = RoomDef.WallMode.BLINK
	blink.variants = [
		RoomVariant.new("classic"),
		RoomVariant.new("fast").blinking(RoomRuntime.BLINK_PERIOD / 2),
	]
	out.append(blink)

	# Gravity Flip: gravity points to the ceiling; flaps push down. Variants:
	# as is; Flip-flop (gravity turns round at every wall bounce).
	var flip := RoomDef.new("flip", "late", 90)
	flip.weight = 8
	flip.gravity_sign = -1
	flip.variants = [RoomVariant.new("classic"), RoomVariant.new("flip-flop").flipping()]
	out.append(flip)

	# Midnight Cage: a dark, crowded cage that runs 25% faster. Variants only
	# change the look (game/): as is; Lantern (a small light round the bird);
	# Flicker (the light pulses).
	var midnight := RoomDef.new("midnight", "late", 100)
	midnight.weight = 8
	midnight.speed = RoomDef.Speed.FAST
	midnight.extra_spikes = 2
	midnight.variants = [
		RoomVariant.new("classic"), RoomVariant.new("lantern"), RoomVariant.new("flicker")
	]
	out.append(midnight)

	return out


## One island per band, swaying `drift` each way (0 = still).
static func islands(drift: int) -> Array[Callable]:
	var out: Array[Callable] = []
	for i in 4:
		out.append(_island.bind(i, drift))
	return out


static func _island(band: int, drift: int) -> Hazard:
	var b := Block.new()
	b.band = band
	b.drift = drift
	return b


static func _big_rock() -> Hazard:
	var b := Block.new()
	b.band = 0
	b.big = true
	return b


static func _twin(lane: int) -> Hazard:
	return Bouncer.new(Bouncer.TWIN_RADIUS, lane)


static func _coin(x: int, y: int, appear_at: int) -> Hazard:
	return CoinPickup.new(x, y, appear_at)


## Orbiting Coins: one coin of the diamond, circling the middle of the room.
static func _orbit_coin(phase: int) -> Hazard:
	return OrbitCoin.new(GARDEN_CX, GARDEN_CY, ORBIT_RADIUS, phase)


## Spiked Decoy: a spiked ball on one of the diamond's spots, in place of the
## coin there (the coins come first; the ball takes one away).
static func _decoy(spots: PackedInt32Array) -> Hazard:
	return SpikeBall.new(spots)
