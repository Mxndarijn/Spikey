extends RefCounted
## Combo rooms: two mid-game hazards at once. Order is part of the rules
## (see RoomCatalog).

const Rotor := preload("res://sim/hazards/rotor.gd")
const Piston := preload("res://sim/hazards/piston.gd")
const Pendulum := preload("res://sim/hazards/pendulum.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const SawRing := preload("res://sim/hazards/saw_ring.gd")
const Stalker := preload("res://sim/hazards/stalker.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Double Trouble: the seed picks one pair whose rhythms only line up now
	# and then. Each pair keeps its hazards in different parts of the room.
	var double := RoomDef.new("double", "late", 120)
	double.weight = 6
	double.max_spikes = 6
	double.combos = [
		[func() -> Hazard: return Rotor.new(), _piston.bind(0, 0, 30)],
		[func() -> Hazard: return Pendulum.new(), _drop.bind(60)],
		[func() -> Hazard: return Bouncer.new(), func() -> Hazard: return Beam.new(3)],
		[func() -> Hazard: return SawRing.new(), func() -> Hazard: return Stalker.new()],
	]
	out.append(double)

	return out


static func _piston(side: int, half: int, delay: int) -> Hazard:
	return Piston.new(side, half, delay)


static func _drop(delay: int) -> Hazard:
	return Drop.new(delay, 10 * SUB, 25)
