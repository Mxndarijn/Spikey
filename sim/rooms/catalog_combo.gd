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

const SUB := SimConfig.SUB
## Warnings inside a combo last 1 s, the reaction time the portal rules allow.
const COMBO_WARN := SimConfig.ARRIVAL_BLIND


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Double Trouble: the seed picks one pair (a variant). So that two hazards
	# never take every way across at once, every pair follows the combo rules
	# (tests/sim/test_double_trouble.gd, tools/fastsim.ps1 -Mode combos):
	# - the partner's danger stays inside the main hazard's band, or is a short
	#   marked event like rain: the lanes the main hazard leaves stay free (the
	#   piston slams at the pinwheel's height);
	# - a hazard that fills a row skips its turn while the other will be in
	#   that row (beams and the ball);
	# - every warning lasts 1 s (COMBO_WARN);
	# - no hazard that follows the bird (Stalker Rail);
	# - each pair carries the arrival skips of its hazards (Lantern Swing's
	#   middle heights), and only pairs that fit are drawn out of a portal.
	var double := RoomDef.new("double", "late", 120)
	double.weight = 6
	double.max_spikes = 6
	double.variants = [
		RoomVariant.new("pinwheel_piston").with(
			[func() -> Hazard: return Rotor.new(), _piston.bind(0, 0, 30)]
		),
		(
			RoomVariant
			. new("swing_rain")
			. with([func() -> Hazard: return Pendulum.new(), _drop.bind(60)])
			. skipping(PackedInt32Array([318 * SUB, 368 * SUB]))
		),
		RoomVariant.new("bramble_beams").with(
			[
				func() -> Hazard: return Bouncer.new(),
				func() -> Hazard: return Beam.new(3, COMBO_WARN, true),
			]
		),
		RoomVariant.new("saw_rain").with([func() -> Hazard: return SawRing.new(), _drop.bind(60)]),
	]
	out.append(double)

	return out


## A piston that glows for 1 s and keeps to the other hazard's band.
static func _piston(side: int, half: int, delay: int) -> Hazard:
	return Piston.new(side, half, delay, COMBO_WARN, true)


## A rain drop marked for 1 s.
static func _drop(delay: int) -> Hazard:
	return Drop.new(delay, 10 * SUB, 25, COMBO_WARN)
