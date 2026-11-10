extends RefCounted
## Seasonal rooms: only picked when the run's season (a run input, stored in
## the replay) matches. Most reuse a year-round hazard with a seasonal skin.
## Order is part of the rules (see RoomCatalog).

const Bouncer := preload("res://sim/hazards/bouncer.gd")
const Block := preload("res://sim/hazards/block.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")
const Mover := preload("res://sim/hazards/mover.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Bumper := preload("res://sim/hazards/bumper.gd")
const Dart := preload("res://sim/hazards/dart.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")
const Crawler := preload("res://sim/hazards/crawler.gd")
const Firework := preload("res://sim/hazards/firework.gd")

const SUB := SimConfig.SUB
## Seasonal rooms are picked more often while their season is on.
const WEIGHT := 12


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Halloween
	var pumpkin := _room("pumpkin", Seasons.HALLOWEEN, 40)
	pumpkin.hazards.append(func() -> Hazard: return Bouncer.new())
	out.append(pumpkin)

	var ghosts := _room("ghostdoors", Seasons.HALLOWEEN, 30)
	ghosts.max_spikes = 6
	# A 2 x 3 grid of doors that fade on a slow cycle, out of step with each other.
	for i in 6:
		ghosts.hazards.append(_ghost_door.bind(i))
	out.append(ghosts)

	# Bat Loop variants: three bats on the eight; a bigger, faster eight; two
	# bats, the second speeding up every lap (capped at 130%).
	var bats := _room("bats", Seasons.HALLOWEEN, 40)
	for shape: String in ["classic", "wide", "pair"]:
		bats.variants.append(RoomVariant.new(shape).with([_bats.bind(shape)]))
	out.append(bats)

	# Winter
	var icicles := _room("icicle", Seasons.WINTER, 50)
	icicles.hazards.append(func() -> Hazard: return Drop.new(30, 10 * SUB, 25))
	icicles.hazards.append(func() -> Hazard: return Drop.new(70, 10 * SUB, 25))
	out.append(icicles)

	var gifts := _room("gifts", Seasons.WINTER, 60)
	# Gifts drop from the ceiling.
	gifts.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	gifts.hazards.append(func() -> Hazard: return CrateDrop.new(true))
	out.append(gifts)

	# Valentine's
	var hearts := _room("hearts", Seasons.VALENTINE, 10)
	hearts.hazards.append(func() -> Hazard: return Bumper.new())
	hearts.hazards.append(func() -> Hazard: return Bumper.new(true))
	out.append(hearts)

	# Cupid Lanes variants: eight lanes; five lanes with arrows in pairs; slow
	# arrows after a long warning.
	var cupid := _room("cupid", Seasons.VALENTINE, 40)
	for shape: String in ["classic", "double", "slow-volley"]:
		cupid.variants.append(
			RoomVariant.new(shape).with([_cupid.bind(shape, 0), _cupid.bind(shape, 1)])
		)
	out.append(cupid)

	# Spring
	var eggs := _room("eggs", Seasons.SPRING, 20)
	eggs.max_spikes = 6
	for band in 4:
		eggs.hazards.append(_island.bind(band))
		eggs.hazards.append(_egg.bind(band))
	out.append(eggs)

	var bees := _room("bees", Seasons.SPRING, 30)
	bees.hazards.append(func() -> Hazard: return Mover.new("wave", 4))
	# Held there, the bird crosses the middle of the bee wave.
	bees.arrival_skip = PackedInt32Array([295 * SUB, 405 * SUB])
	out.append(bees)

	# Summer
	var beach := _room("beachball", Seasons.SUMMER, 40)
	beach.group = "bonus"
	beach.max_spikes = 3
	beach.hazards.append(func() -> Hazard: return KeepyBall.new())
	out.append(beach)

	var crabs := _room("crabs", Seasons.SUMMER, 30)
	# A crab walks the ceiling.
	crabs.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	crabs.hazards.append(func() -> Hazard: return Crawler.new(0))
	crabs.hazards.append(func() -> Hazard: return Crawler.new(1))
	out.append(crabs)

	# New Year
	# Firework Burst variants: a ring of sparks; a ring and then a second one
	# (two rockets); a cross of sparks.
	var fireworks := _room("fireworks", Seasons.NEW_YEAR, 50)
	var styles := {
		"classic": Firework.Style.RING,
		"double": Firework.Style.DOUBLE,
		"cross": Firework.Style.CROSS,
	}
	for shape: String in styles:
		var rockets: Array[Callable] = []
		# A double burst covers twice the sky, so it has two rockets, not three.
		var delays := [0, 75] if shape == "double" else [0, 50, 100]
		for delay: int in delays:
			rockets.append(_firework.bind(delay, styles[shape]))
		fireworks.variants.append(RoomVariant.new(shape).with(rockets))
	out.append(fireworks)

	var countdown := _room("countdown", Seasons.NEW_YEAR, 20)
	countdown.group = "bonus"
	countdown.max_spikes = 2
	# Ten coins light up one per second around the middle of the room.
	for i in 10:
		var angle := i * SimTrig.TURN / 10
		var x := 180 * SUB + 100 * SUB * SimTrig.cos_t(angle) / SimTrig.ONE
		var y := 320 * SUB + 130 * SUB * SimTrig.sin_t(angle) / SimTrig.ONE
		countdown.hazards.append(_coin.bind(x, y, i * SimConfig.TICKS_PER_SECOND))
	out.append(countdown)

	return out


static func _room(id: String, season: int, from: int) -> RoomDef:
	var def := RoomDef.new(id, "seasonal", from)
	def.season = season
	def.weight = WEIGHT
	return def


static func _ghost_door(i: int) -> Hazard:
	var col := i % 2
	var row := i / 2
	var x0 := (90 + col * 120) * SUB
	var y0 := (190 + row * 130) * SUB
	var b := Block.new(x0, y0, x0 + 60 * SUB, y0 + 34 * SUB)
	b.fade_period = 240
	b.solid_ticks = 140
	b.phase = i * 40
	return b


static func _island(band: int) -> Hazard:
	var b := Block.new()
	b.band = band
	return b


## An egg next to the island of the same band (CoinPickup.beside_band: it finds
## the island, built and placed just before it, in setup()).
static func _egg(band: int) -> Hazard:
	var egg := CoinPickup.new()
	egg.beside_band = band
	return egg


static func _coin(x: int, y: int, appear_at: int) -> Hazard:
	return CoinPickup.new(x, y, appear_at)


static func _firework(delay: int, style: int) -> Hazard:
	return Firework.new(delay, style)


## One Bat Loop variant.
static func _bats(shape: String) -> Hazard:
	match shape:
		"wide":
			# 30% wider and taller, a lap in 380 steps instead of 480.
			var wide := Mover.new("figure8", 3)
			wide.loop_w = 104 * SUB
			wide.loop_h = 112 * SUB
			wide.loop_period = 380
			return wide
		"pair":
			var pair := Mover.new("figure8", 2)
			pair.loop_period = 400
			pair.chase = true
			return pair
	return Mover.new("figure8", 3)


## One of the two Cupid Lanes darts (`slot` 0 or 1) of a variant.
static func _cupid(shape: String, slot: int) -> Hazard:
	var d := Dart.new(true, slot)
	match shape:
		"double":
			# Five lanes 90 px apart, two arrows a shot.
			d.lane_count = 5
			d.lane_min = 110 * SUB
			d.lane_max = 470 * SUB
			d.pair = true
		"slow-volley":
			# Half speed, a 1.4 s warning.
			d.lanes_speed = 3 * SUB
			d.lanes_flash = 84
	return d
