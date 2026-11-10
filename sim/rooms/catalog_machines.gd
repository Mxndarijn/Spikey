extends RefCounted
## Rooms batch: machines. Order is part of the rules (see RoomCatalog).

const Piston := preload("res://sim/hazards/piston.gd")
const EdgePad := preload("res://sim/hazards/edge_pad.gd")
const PadCoin := preload("res://sim/hazards/pad_coin.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const Stalactite := preload("res://sim/hazards/stalactite.gd")
const Dart := preload("res://sim/hazards/dart.gd")

const SUB := SimConfig.SUB

## Double slam: how far each ram reaches (a gap stays between the two tips)
## and its warning glow (1 s).
const SLAM_REACH := 150 * SUB
const SLAM_GLOW := 60
## Ladder: the rungs' heights, how far they reach, steps between rungs.
const LADDER_Y: Array[int] = [170 * SUB, 300 * SUB, 430 * SUB]
const LADDER_REACH := 140 * SUB
const LADDER_BEAT := 36
## Wide crates: four columns of 70 px, crates 64 x 48, stacks of up to three
## (as tall as a classic full stack).
const WIDE_COLS := 4
const WIDE_COL_W := 70 * SUB
const WIDE_W := 64 * SUB
const WIDE_H := 48 * SUB
const WIDE_MAX := 3
## Stalactite Run, floor fangs: the gap the one rock leaves (so its tip sits
## half of it below the gap's centre).
const FANG_GAP := 100 * SUB
## Three-column variants: where the columns stand (px).
const TRIO_X: Array[int] = [75, 180, 285]
## Alternating: the open middle (tip to tip) and where its centre can be
## (it starts round the bird's hop); out of a portal only where a bird
## holding its height (hopping up to 62 px) clears every finger.
const ALT_GAP := 150 * SUB
const ALT_LO := 260 * SUB
const ALT_HI := 380 * SUB
const ALT_ARRIVAL_LO := 270 * SUB
const ALT_ARRIVAL_HI := 430 * SUB
## Short fangs: a 300 px corridor round the middle, thinner rocks; out of a
## portal only where a bird holding its height stays inside it.
const SHORT_GAP := 300 * SUB
const SHORT_Y := 320 * SUB
const SHORT_HALF_W := 18 * SUB
const SHORT_ARRIVAL_LO := 256 * SUB
const SHORT_ARRIVAL_HI := 448 * SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Piston Press: pistons glow, slam across part of the room, hold and pull
	# back. Classic: one in each wall, one high and one low, taking turns.
	# Double slam: one in each wall at the same height, firing together (a 1 s
	# glow, and a gap between the rams). Ladder: three in the right wall at
	# fixed heights, firing top to bottom like a wave.
	var piston := RoomDef.new("piston", "mid", 30)
	piston.max_spikes = 6
	piston.variants = [
		RoomVariant.new("classic").with(
			[_piston.bind(0, 0, 30), _piston.bind(1, 1, 30 + Piston.PERIOD / 2)]
		),
		RoomVariant.new("double-slam").with([_slam.bind(0), _slam.bind(1)]),
		RoomVariant.new("ladder").with([_rung.bind(0), _rung.bind(1), _rung.bind(2)]),
	]
	out.append(piston)

	# Bumper Court: a pad slides along the ceiling and one along the floor;
	# they bounce the bird, the rest of the edge still kills. Variants: classic;
	# goal-pad (a coin rides the floor pad: land on it to take it, and the next
	# one shows up on the other pad).
	var court := RoomDef.new("court", "mid", 40)
	court.hazards.append(_pad.bind(true, 300))
	court.hazards.append(_pad.bind(false, 240))
	court.variants = [
		RoomVariant.new("classic"),
		RoomVariant.new("goal-pad").with([func() -> Hazard: return PadCoin.new(false)]),
	]
	out.append(court)

	# Crate Drop: crates fall one at a time and pile up in columns (classic),
	# or big crates make fat towers (wide), or two fall at once (pairs).
	var crates := RoomDef.new("crates", "mid", 60)
	crates.max_spikes = 6
	crates.variants = crate_variants(false)
	out.append(crates)

	# Beam Gates: four wall-to-wall beams firing in turn, with a warning first.
	var beams := RoomDef.new("beams", "mid", 50)
	beams.max_spikes = 5
	beams.hazards.append(func() -> Hazard: return Beam.new())
	out.append(beams)

	# Stalactite Run: rock columns with a gap. Classic: two columns whose gaps
	# move on every bounce. Floor fangs / ceiling only: the same, with only
	# the rocks from the floor / the ceiling. Alternating: three long fingers,
	# hanging, standing, hanging, around an open middle that stays put. Short
	# fangs: three short columns around a 300 px corridor that never moves.
	var stalac := RoomDef.new("stalac", "mid", 30)
	stalac.max_spikes = 4
	# The gap can't come up far enough for a hop near the top.
	stalac.arrival_skip = PackedInt32Array([0, RoomDef.CEILING_ARRIVAL])
	stalac.variants = [
		RoomVariant.new("classic").with(
			[_stalactite.bind(130 * SUB, false), _stalactite.bind(230 * SUB, true)]
		),
		RoomVariant.new("floor").with(
			[_fang.bind(130, false, false), _fang.bind(230, true, false)]
		),
		RoomVariant.new("ceiling-only").with(
			[_fang.bind(130, false, true), _fang.bind(230, true, true)]
		),
		(
			RoomVariant
			. new("alternating")
			. with([_finger.bind(0), _finger.bind(1), _finger.bind(2)])
			. skipping(PackedInt32Array([0, ALT_ARRIVAL_LO, ALT_ARRIVAL_HI, SimConfig.WORLD_H]))
		),
		(
			RoomVariant
			. new("short-fangs")
			. with([_short.bind(0), _short.bind(1), _short.bind(2)])
			. skipping(PackedInt32Array([0, SHORT_ARRIVAL_LO, SHORT_ARRIVAL_HI, SimConfig.WORLD_H]))
		),
	]
	out.append(stalac)

	# Hunter Spike: a spike on the far wall aims at the bird's height and fires.
	# Variants: the classic one; twin hunters, one on each wall, taking turns.
	var hunter := RoomDef.new("hunter", "late", 80)
	hunter.weight = 8
	hunter.variants = [
		RoomVariant.new("classic").with([func() -> Hazard: return Dart.new()]),
		RoomVariant.new("twin").with([_hunter.bind(0, 1), _hunter.bind(1, 0)]),
	]
	out.append(hunter)

	return out


## Crate Drop's variants; Winter Gift Stack has the same ones with gifts.
static func crate_variants(gifts: bool) -> Array[RoomVariant]:
	var out: Array[RoomVariant] = [
		RoomVariant.new("classic").with([_crates.bind(gifts, false, false)]),
		RoomVariant.new("wide").with([_crates.bind(gifts, true, false)]),
		RoomVariant.new("pairs").with([_crates.bind(gifts, false, true)]),
	]
	return out


static func _crates(gifts: bool, wide: bool, pair: bool) -> Hazard:
	if wide:
		return CrateDrop.new(gifts, WIDE_COLS, WIDE_COL_W, WIDE_W, WIDE_H, WIDE_MAX, pair)
	return CrateDrop.new(
		gifts,
		CrateDrop.COLS,
		CrateDrop.COL_W,
		CrateDrop.CRATE,
		CrateDrop.CRATE,
		CrateDrop.MAX_HEIGHT,
		pair
	)


static func _piston(side: int, half: int, delay: int) -> Hazard:
	return Piston.new(side, half, delay)


## Twin hunters: dart `slot` fires from wall `home`.
static func _hunter(slot: int, home: int) -> Hazard:
	return Dart.new(false, slot, home)


## Double slam: both rams at one height (the right one copies the left).
static func _slam(side: int) -> Hazard:
	var p := Piston.new(side, Piston.HALF_ALL, 30, SLAM_GLOW)
	p.reach = SLAM_REACH
	p.follows = side == 1
	return p


## Ladder: rung i of three in the right wall, each a beat after the one above.
static func _rung(i: int) -> Hazard:
	var p := Piston.new(1, 0, 30 + i * LADDER_BEAT)
	p.reach = LADDER_REACH
	p.fixed_y = LADDER_Y[i]
	return p


static func _pad(top: bool, period: int) -> Hazard:
	return EdgePad.new(top, period)


static func _stalactite(x: int, follows: bool) -> Hazard:
	return Stalactite.new(x, follows)


## Floor fangs (ceiling false) or ceiling only (ceiling true): one rock.
static func _fang(x_px: int, follows: bool, ceiling: bool) -> Hazard:
	var s := Stalactite.new(x_px * SUB, follows)
	s.top = ceiling
	s.bottom = not ceiling
	# A hanging rock keeps the classic 75 px over the gap: a bird holding its
	# height hops that high.
	s.gap = Stalactite.GAP if ceiling else FANG_GAP
	return s


## Alternating: column i hangs (even) or stands (odd); the first one leads.
static func _finger(i: int) -> Hazard:
	var s := Stalactite.new(TRIO_X[i] * SUB, i > 0)
	s.top = i % 2 == 0
	s.bottom = i % 2 == 1
	s.gap = ALT_GAP
	s.fixed_lo = ALT_LO
	s.fixed_hi = ALT_HI
	return s


## Short fangs: column i of three, both rocks short.
static func _short(i: int) -> Hazard:
	var s := Stalactite.new(TRIO_X[i] * SUB, i > 0)
	s.gap = SHORT_GAP
	s.half_w = SHORT_HALF_W
	s.fixed_lo = SHORT_Y
	s.fixed_hi = SHORT_Y
	return s
