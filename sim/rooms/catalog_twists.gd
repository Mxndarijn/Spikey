extends RefCounted
## Rooms batch: twists. Rooms that change a rule of the cage: wind across the
## room, spikes that ride the wall, a locked exit, a rising floor, a shadow of
## the bird. Each hazard reads the room's variant in setup(). Order is part of
## the rules (see RoomCatalog).

const Wind := preload("res://sim/hazards/wind.gd")
const Belt := preload("res://sim/hazards/belt.gd")
const ExitKey := preload("res://sim/hazards/exit_key.gd")
const Lava := preload("res://sim/hazards/lava.gd")
const Echo := preload("res://sim/hazards/echo.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Crosswind: a band of wind speeds the bird up one way and slows it the
	# other. Variants: one band; two opposite bands; a band that gusts.
	var wind := RoomDef.new("crosswind", "starter", 10)
	wind.hazards.append(func() -> Hazard: return Wind.new())
	wind.variants = [RoomVariant.new("steady"), RoomVariant.new("split"), RoomVariant.new("gusty")]
	out.append(wind)

	# Spike Belt: the spikes on the wall ahead slide along it. Variants: both
	# belts up; left up and right down; both reverse at every wall.
	var belt := RoomDef.new("belt", "starter", 20)
	belt.hazards.append(func() -> Hazard: return Belt.new())
	belt.variants = [
		RoomVariant.new("up"), RoomVariant.new("counter"), RoomVariant.new("switchback")
	]
	out.append(belt)

	# Locked Out: the exit opens locked until the bird has every key; while it
	# is locked the walls grow spikes. Every variant has one more spike per wall.
	# Variants: three keys; four keys; three keys one at a time.
	var lock := RoomDef.new("lockexit", "mid", 40)
	lock.hazards.append(func() -> Hazard: return ExitKey.new())
	lock.variants = [
		RoomVariant.new("trio").sized(1, 1, 1),
		RoomVariant.new("quad").sized(1, 1, 1),
		RoomVariant.new("chain").sized(1, 1, 1),
	]
	out.append(lock)

	# Lava Rise: lava climbs a step for every point; something sinks it again.
	# Variants: a cool stone (lava); an ice block in a wall slot to bounce on
	# (cold); rafts of cooled rock to bump off (rafts).
	var lava := RoomDef.new("lava", "mid", 50)
	lava.max_spikes = 6
	lava.hazards.append(func() -> Hazard: return Lava.new())
	lava.variants = [RoomVariant.new("lava"), RoomVariant.new("cold"), RoomVariant.new("rafts")]
	out.append(lava)

	# Echo: a shadow bird flies the bird's path a second late, or mirrors it
	# through the middle of the room.
	# The mirror is GENERATED: out of a portal the height it turns round is
	# drawn away from the band a bird holding its height sweeps (held level
	# with that height, the bird meets its mirror in the middle).
	var echo := RoomDef.new("echo", "late", 80)
	echo.weight = 8
	echo.variants = [
		RoomVariant.new("echo").with([func() -> Hazard: return Echo.new(Echo.Mode.ECHO)]),
		RoomVariant.new("mirror").generated(_gen_mirror),
	]
	out.append(echo)

	return out


## Generated Echo, mirror: the shadow turns the bird round a drawn height.
static func _gen_mirror(p: VariantParams) -> void:
	var e: Hazard = p.add(Echo.new(Echo.Mode.MIRROR))
	e.place_pivot(p)
