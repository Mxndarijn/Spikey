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
	# Variants: one key by a wall; one on a wide orbit; three keys; four keys;
	# three keys one at a time.
	var lock := RoomDef.new("lockexit", "mid", 40)
	lock.hazards.append(func() -> Hazard: return ExitKey.new())
	lock.variants = [
		RoomVariant.new("classic").sized(1, 1, 1),
		RoomVariant.new("orbit").sized(1, 1, 1),
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
	var echo := RoomDef.new("echo", "late", 80)
	echo.weight = 8
	# Mirror: held at mid height, the bird meets its mirror in the middle.
	echo.arrival_skip = PackedInt32Array([280 * SUB, 360 * SUB])
	echo.hazards.append(func() -> Hazard: return Echo.new())
	echo.variants = [RoomVariant.new("echo"), RoomVariant.new("mirror")]
	out.append(echo)

	return out
