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

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Open Sky: the classic cage, where every run starts.
	out.append(RoomDef.new("open", "starter", 0))

	var crowded := RoomDef.new("crowded", "starter", 10)
	crowded.extra_spikes = 1
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

	# Floating Isles: four still islands, one per band of the room.
	var isles := RoomDef.new("isles", "starter", 10)
	isles.max_spikes = 6
	for i in 4:
		isles.hazards.append(_island.bind(i))
	out.append(isles)

	# Coin Garden: a breather with up to three spikes per wall and four coins.
	# Every bounce adds a coin, even when one is already out.
	var garden := RoomDef.new("garden", "bonus", 20)
	garden.weight = 4
	garden.max_spikes = 3
	garden.bounce_coin_stacks = true
	# A diamond of coins: [x, y] in pixels.
	for p: Array in [[180, 220], [120, 320], [240, 320], [180, 420]]:
		garden.hazards.append(_coin.bind(int(p[0]) * SUB, int(p[1]) * SUB, 0))
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

	# Squeeze Box: every point here moves both walls in a step.
	var squeeze := RoomDef.new("squeeze", "mid", 50)
	squeeze.squeeze = true
	out.append(squeeze)

	# Slow-Mo Breather: everything at half speed, an arc of coins, few spikes.
	var slowmo := RoomDef.new("slowmo", "bonus", 60)
	slowmo.weight = 4
	slowmo.speed = RoomDef.Speed.SLOW
	slowmo.max_spikes = 2
	var arc: Array[int] = [0, 60, 80, 60, 0]
	for i in 5:
		var x := (90 + i * 45) * SUB
		var y := (330 - arc[i]) * SUB
		slowmo.hazards.append(_coin.bind(x, y, 0))
	out.append(slowmo)

	# Blink Walls: each wall flips between two spike patterns every second.
	var blink := RoomDef.new("blink", "late", 80)
	blink.weight = 8
	blink.wall_mode = RoomDef.WallMode.BLINK
	out.append(blink)

	# Gravity Flip: gravity points to the ceiling; flaps push down.
	var flip := RoomDef.new("flip", "late", 90)
	flip.weight = 8
	flip.gravity_sign = -1
	out.append(flip)

	# Midnight Cage: a dark, crowded cage that runs 25% faster.
	var midnight := RoomDef.new("midnight", "late", 100)
	midnight.weight = 8
	midnight.speed = RoomDef.Speed.FAST
	midnight.extra_spikes = 2
	out.append(midnight)

	return out


static func _island(band: int) -> Hazard:
	var b := Block.new()
	b.band = band
	return b


static func _twin(lane: int) -> Hazard:
	return Bouncer.new(Bouncer.TWIN_RADIUS, lane)


static func _coin(x: int, y: int, appear_at: int) -> Hazard:
	return CoinPickup.new(x, y, appear_at)
