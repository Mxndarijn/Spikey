extends RefCounted
## Rooms batch: machines. Order is part of the rules (see RoomCatalog).

const Piston := preload("res://sim/hazards/piston.gd")
const EdgePad := preload("res://sim/hazards/edge_pad.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const Stalactite := preload("res://sim/hazards/stalactite.gd")
const Dart := preload("res://sim/hazards/dart.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Piston Press: a piston in each wall, one high and one low, taking turns:
	# each glows, slams across part of the room, holds and pulls back.
	var piston := RoomDef.new("piston", "mid", 30)
	piston.max_spikes = 6
	piston.hazards.append(_piston.bind(0, 0, 30))
	piston.hazards.append(_piston.bind(1, 1, 30 + Piston.PERIOD / 2))
	out.append(piston)

	# Bumper Court: a pad slides along the ceiling and one along the floor;
	# they bounce the bird, the rest of the edge still kills.
	var court := RoomDef.new("court", "mid", 40)
	court.hazards.append(_pad.bind(true, 300))
	court.hazards.append(_pad.bind(false, 240))
	out.append(court)

	# Crate Drop: crates fall one at a time and pile up in columns.
	var crates := RoomDef.new("crates", "mid", 60)
	crates.max_spikes = 6
	crates.hazards.append(func() -> Hazard: return CrateDrop.new())
	out.append(crates)

	# Beam Gates: four wall-to-wall beams firing in turn, with a warning first.
	var beams := RoomDef.new("beams", "mid", 50)
	beams.max_spikes = 5
	beams.hazards.append(func() -> Hazard: return Beam.new())
	out.append(beams)

	# Stalactite Run: two rock columns with a gap; the gaps move on every bounce.
	var stalac := RoomDef.new("stalac", "mid", 30)
	stalac.max_spikes = 4
	# The gap can't come up far enough for a hop near the top.
	stalac.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	stalac.hazards.append(_stalactite.bind(130 * SUB, false))
	stalac.hazards.append(_stalactite.bind(230 * SUB, true))
	out.append(stalac)

	# Hunter Spike: a spike on the far wall aims at the bird's height and fires.
	var hunter := RoomDef.new("hunter", "late", 80)
	hunter.weight = 8
	hunter.hazards.append(func() -> Hazard: return Dart.new())
	out.append(hunter)

	return out


static func _piston(side: int, half: int, delay: int) -> Hazard:
	return Piston.new(side, half, delay)


static func _pad(top: bool, period: int) -> Hazard:
	return EdgePad.new(top, period)


static func _stalactite(x: int, follows: bool) -> Hazard:
	return Stalactite.new(x, follows)
