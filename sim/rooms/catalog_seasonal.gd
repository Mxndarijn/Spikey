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
## Egg Hunt: islands built so far in the room, so each egg can sit next to one.
static var _nest: Array[Hazard] = []


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Halloween
	var pumpkin := _room("pumpkin", Seasons.HALLOWEEN, 40, "pumpkin")
	pumpkin.hazards.append(func() -> Hazard: return Bouncer.new())
	out.append(pumpkin)

	var ghosts := _room("ghostdoors", Seasons.HALLOWEEN, 30, "ghost")
	ghosts.max_spikes = 6
	# A 2 x 3 grid of doors that fade on a slow cycle, out of step with each other.
	for i in 6:
		ghosts.hazards.append(_ghost_door.bind(i))
	out.append(ghosts)

	var bats := _room("bats", Seasons.HALLOWEEN, 40, "bat")
	bats.hazards.append(func() -> Hazard: return Mover.new("figure8", 3))
	out.append(bats)

	# Winter
	var icicles := _room("icicle", Seasons.WINTER, 50, "icicle")
	icicles.hazards.append(func() -> Hazard: return Drop.new(30, 10 * SUB, 25))
	icicles.hazards.append(func() -> Hazard: return Drop.new(70, 10 * SUB, 25))
	out.append(icicles)

	var gifts := _room("gifts", Seasons.WINTER, 60, "gift")
	# Gifts drop from the ceiling.
	gifts.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	gifts.hazards.append(func() -> Hazard: return CrateDrop.new(true))
	out.append(gifts)

	# Valentine's
	var hearts := _room("hearts", Seasons.VALENTINE, 10, "heart")
	hearts.hazards.append(func() -> Hazard: return Bumper.new())
	hearts.hazards.append(func() -> Hazard: return Bumper.new(true))
	out.append(hearts)

	var cupid := _room("cupid", Seasons.VALENTINE, 40, "cupid")
	cupid.hazards.append(func() -> Hazard: return Dart.new(true, 0))
	cupid.hazards.append(func() -> Hazard: return Dart.new(true, 1))
	out.append(cupid)

	# Spring
	var eggs := _room("eggs", Seasons.SPRING, 20, "egg")
	eggs.max_spikes = 6
	for band in 4:
		eggs.hazards.append(_island.bind(band))
		eggs.hazards.append(_egg.bind(band))
	out.append(eggs)

	var bees := _room("bees", Seasons.SPRING, 30, "bee")
	bees.hazards.append(func() -> Hazard: return Mover.new("wave", 4))
	# Held there, the bird crosses the middle of the bee wave.
	bees.arrival_skip = PackedInt32Array([295 * SUB, 405 * SUB])
	out.append(bees)

	# Summer
	var beach := _room("beachball", Seasons.SUMMER, 40, "beachball")
	beach.group = "bonus"
	beach.max_spikes = 3
	beach.hazards.append(func() -> Hazard: return KeepyBall.new())
	out.append(beach)

	var crabs := _room("crabs", Seasons.SUMMER, 30, "crab")
	# A crab walks the ceiling.
	crabs.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	crabs.hazards.append(func() -> Hazard: return Crawler.new(0))
	crabs.hazards.append(func() -> Hazard: return Crawler.new(1))
	out.append(crabs)

	# New Year
	var fireworks := _room("fireworks", Seasons.NEW_YEAR, 50, "")
	for delay in [0, 50, 100]:
		fireworks.hazards.append(_firework.bind(delay))
	out.append(fireworks)

	var countdown := _room("countdown", Seasons.NEW_YEAR, 20, "")
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


static func _room(id: String, season: int, from: int, skin: String) -> RoomDef:
	var def := RoomDef.new(id, "seasonal", from)
	def.season = season
	def.weight = WEIGHT
	def.skin = skin
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
	if band == 0:
		_nest.clear()
	_nest.append(b)
	return b


## An egg next to the island of the same band (built just before it, so the
## island is already placed when this runs).
static func _egg(band: int) -> Hazard:
	var island: Hazard = _nest[band]
	var gap := 22 * SUB
	var x: int = island.x1 + gap if island.x1 + gap <= 290 * SUB else island.x0 - gap
	var y: int = (island.y0 + island.y1) / 2
	var egg := CoinPickup.new(x, y, 0)
	return egg


static func _coin(x: int, y: int, appear_at: int) -> Hazard:
	return CoinPickup.new(x, y, appear_at)


static func _firework(delay: int) -> Hazard:
	return Firework.new(delay)
