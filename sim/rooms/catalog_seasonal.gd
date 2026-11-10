extends RefCounted
## Seasonal rooms: only picked when the run's season (a run input, stored in
## the replay) matches. Most reuse a year-round hazard with a seasonal skin.
## Order is part of the rules (see RoomCatalog).

const Bouncer := preload("res://sim/hazards/bouncer.gd")
const SplittingBouncer := preload("res://sim/hazards/splitting_bouncer.gd")
const Block := preload("res://sim/hazards/block.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")
const Mover := preload("res://sim/hazards/mover.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Bumper := preload("res://sim/hazards/bumper.gd")
const Dart := preload("res://sim/hazards/dart.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")
const Firework := preload("res://sim/hazards/firework.gd")
const CatalogMotion := preload("res://sim/rooms/catalog_motion.gd")

const SUB := SimConfig.SUB
## Seasonal rooms are picked more often while their season is on.
const WEIGHT := 12
## Ghost Doors, one row: the doors' top edge, size, the steps per cycle and
## how long each is solid. Each door is open for a third of the cycle, one
## after the other.
const ROW_Y := 400
const ROW_W := 60
const ROW_H := 34
const ROW_PERIOD := 240
const ROW_SOLID := 160
## Out of a portal the row variant skips these heights (px): a bird holding
## height there (it hops about 62 px over the line) meets the row.
const ROW_SKIP := [380 * SimConfig.SUB, 516 * SimConfig.SUB]
## Ghost Doors, flicker: a short cycle (2.5 s, solid for 1 s), each row of
## doors further into it than the one above, the right door a little more.
## Steps per row and per column apart: with both doors of a row far apart in
## time, out of a portal no timing lets a bird holding height through.
const FLICKER_PERIOD := 150
const FLICKER_SOLID := 60
const FLICKER_ROW_STEP := 50
const FLICKER_COL_STEP := 20


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Halloween
	# Pumpkin Bounce is Bramble Ball with a skin. Variants: the classic ball;
	# two smaller ones in the upper and lower lanes; one that splits in two.
	var pumpkin := _room("pumpkin", Seasons.HALLOWEEN, 40)
	pumpkin.variants = [
		RoomVariant.new("classic").with([func() -> Hazard: return Bouncer.new()]),
		RoomVariant.new("twin").with(
			[_twin.bind(Bouncer.Lane.UPPER), _twin.bind(Bouncer.Lane.LOWER)]
		),
		RoomVariant.new("splitting").with([func() -> Hazard: return SplittingBouncer.new()]),
	]
	out.append(pumpkin)

	var ghosts := _room("ghostdoors", Seasons.HALLOWEEN, 30)
	ghosts.max_spikes = 6
	# A 2 x 3 grid of doors that fade on a slow cycle, out of step with each
	# other. Variants: that grid; one row of three doors that open in turn,
	# left to right; the grid fading fast and out of step (flicker).
	var grid: Array[Callable] = []
	var flicker: Array[Callable] = []
	for i in 6:
		grid.append(_ghost_door.bind(i))
		flicker.append(_flicker_door.bind(i))
	var row: Array[Callable] = []
	for i in 3:
		row.append(_row_door.bind(i))
	ghosts.variants = [
		RoomVariant.new("classic").with(grid),
		# Out of a portal level with the row, a bird holding height flies
		# through all three doors, and only one is ever open.
		RoomVariant.new("row").with(row).skipping(PackedInt32Array(ROW_SKIP)),
		RoomVariant.new("flicker").with(flicker),
	]
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
	# Heart Bumpers is Bumper Cloud with a skin. Variants: two hearts on
	# opposite sides of the loop; one big heart; two hearts circling the middle.
	var hearts := _room("hearts", Seasons.VALENTINE, 10)
	hearts.variants = [
		RoomVariant.new("classic").with(
			[func() -> Hazard: return Bumper.new(), func() -> Hazard: return Bumper.new(true)]
		),
		RoomVariant.new("one-big").with([func() -> Hazard: return Bumper.new().big()]),
		RoomVariant.new("orbit").with(
			[
				func() -> Hazard: return Bumper.new().orbit(),
				func() -> Hazard: return Bumper.new(true).orbit(),
			]
		),
	]
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
	# Egg Hunt: Floating Isles with an egg beside each island. Variants: still
	# isles; drifting isles (the eggs ride along); a golden egg worth
	# CoinPickup.GOLD_VALUE behind the lowest isle.
	var eggs := _room("eggs", Seasons.SPRING, 20)
	eggs.max_spikes = 6
	eggs.variants = [
		RoomVariant.new("classic").with(_egg_isles(0, false)),
		RoomVariant.new("drifting").with(_egg_isles(Block.DRIFT, false)),
		RoomVariant.new("golden").with(_egg_isles(0, true)),
	]
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
	# Keepy-Uppy with a beach ball. Variants: one ball; two to keep up at
	# once; a heavy ball with low, short bounces.
	beach.variants = [
		RoomVariant.new("classic").with([func() -> Hazard: return KeepyBall.new()]),
		RoomVariant.new("two").with(
			[
				func() -> Hazard: return KeepyBall.new().dropping(0),
				func() -> Hazard: return KeepyBall.new().dropping(KeepyBall.SECOND_DROP),
			]
		),
		RoomVariant.new("heavy").with([func() -> Hazard: return KeepyBall.new().heavy()]),
	]
	out.append(beach)

	# Caterpillar Crawl with crabs, and the same variants.
	var crabs := _room("crabs", Seasons.SUMMER, 30)
	# A crab walks the ceiling.
	crabs.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	crabs.variants = CatalogMotion.crawl_variants()
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


static func _twin(lane: int) -> Hazard:
	return Bouncer.new(Bouncer.TWIN_RADIUS, lane)


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


## Ghost Doors, one row: three doors across the lower middle, 60 px from the
## walls and 30 px apart, opening in turn from the left.
static func _row_door(i: int) -> Hazard:
	var x0 := (60 + i * 90) * SUB
	var y0 := ROW_Y * SUB
	var b := Block.new(x0, y0, x0 + ROW_W * SUB, y0 + ROW_H * SUB)
	b.fade_period = ROW_PERIOD
	b.solid_ticks = ROW_SOLID
	# Door i is open (not solid) for room steps i * 80 to i * 80 + 80 of each cycle.
	b.phase = posmod(ROW_SOLID - i * (ROW_PERIOD - ROW_SOLID), ROW_PERIOD)
	b.guards_exit = true
	return b


## Ghost Doors, flicker: the grid of doors on a short cycle, out of step.
static func _flicker_door(i: int) -> Hazard:
	var b := _ghost_door(i) as Block
	b.fade_period = FLICKER_PERIOD
	b.solid_ticks = FLICKER_SOLID
	b.phase = ((i / 2) * FLICKER_ROW_STEP + (i % 2) * FLICKER_COL_STEP) % FLICKER_PERIOD
	return b


## Egg Hunt: an island per band, each with its egg right after it. Golden:
## the lowest isle's egg is golden and sits behind it.
static func _egg_isles(drift: int, golden: bool) -> Array[Callable]:
	var out: Array[Callable] = []
	for band in 4:
		out.append(_island.bind(band, drift))
		out.append(_egg.bind(band, golden and band == 3))
	return out


static func _island(band: int, drift: int) -> Hazard:
	var b := Block.new()
	b.band = band
	b.drift = drift
	return b


## An egg next to the island of the same band (CoinPickup.beside_band: it finds
## the island, built and placed just before it, in setup()).
static func _egg(band: int, golden: bool) -> Hazard:
	var egg := CoinPickup.new()
	egg.beside_band = band
	if golden:
		egg.value = CoinPickup.GOLD_VALUE
		egg.behind = true
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
