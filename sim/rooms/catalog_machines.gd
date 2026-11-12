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
## Two-column Stalactite variants: which rocks a column has.
const BOTH := 0
const FLOOR := 1
const CEILING := 2
## Three-column variants: where the columns stand (px).
const TRIO_X: Array[int] = [75, 180, 285]
## Alternating: the open middle (tip to tip) and where its centre can be
## (it starts round the bird's hop); out of a portal only where a bird
## holding its height (hopping up to 62 px) clears every finger.
const ALT_GAP := 150 * SUB
const ALT_LO := 260 * SUB
const ALT_HI := 380 * SUB
## Generated alternating: where the open middle can be (it follows the entry).
const ALT_GEN_LO := 220 * SUB
const ALT_GEN_HI := 420 * SUB
## Short fangs: a 300 px corridor round the middle, thinner rocks; out of a
## portal only where a bird holding its height stays inside it.
const SHORT_GAP := 300 * SUB
const SHORT_Y := 320 * SUB
const SHORT_HALF_W := 18 * SUB
## Generated short fangs: where the corridor's middle can be (it follows the
## entry; the hand-made one is always at SHORT_Y).
const SHORT_GEN_LO := 250 * SUB
const SHORT_GEN_HI := 390 * SUB


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
	# Every variant is GENERATED round the planned
	# entry height: out of a portal their gaps open round the band a bird
	# holding its height anywhere in the exit sweeps, until it is past
	# (Stalactite.open_for_arrival), so they fit every arrival height.
	var stalac := RoomDef.new("stalac", "mid", 30)
	stalac.max_spikes = 4
	stalac.variants = [
		RoomVariant.new("classic").generated(_gen_columns.bind(BOTH)),
		RoomVariant.new("floor").generated(_gen_columns.bind(FLOOR)),
		RoomVariant.new("ceiling-only").generated(_gen_columns.bind(CEILING)),
		RoomVariant.new("alternating").generated(_gen_fixed.bind(false)),
		RoomVariant.new("short-fangs").generated(_gen_fixed.bind(true)),
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


## Crate Drop's variants; Winter Gift Stack has the same ones with gifts,
## GENERATED: gifts drop from the ceiling, so out of a portal the columns are
## drawn again until the first gifts miss a bird holding its height for
## FairLanes.ARRIVAL_PATH_TICKS (the first one falls after the reading time).
static func crate_variants(gifts: bool) -> Array[RoomVariant]:
	var shapes := [["classic", false, false], ["wide", true, false], ["pairs", false, true]]
	var out: Array[RoomVariant] = []
	for sh: Array in shapes:
		var v := RoomVariant.new(sh[0])
		if gifts:
			v.generated(_gen_crates.bind(sh[1], sh[2]), false, FairLanes.ARRIVAL_PATH_TICKS)
		else:
			v.with([_crates.bind(false, sh[1], sh[2])])
		out.append(v)
	return out


## Generated Gift Stack: the crates as hand made (they draw their columns).
## The fallback holds the first gift back for the arrival path's length more,
## its column marked all that time.
static func _gen_crates(p: VariantParams, wide: bool, pair: bool) -> void:
	var c: Hazard = p.add(_crates(true, wide, pair))
	if p.fallback and p.arriving:
		c.warn_left += FairLanes.ARRIVAL_PATH_TICKS


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


## Generated Stalactite Run, classic (BOTH rocks), floor fangs or ceiling
## only: two columns, the second following the first, their gaps opened for
## the arrival. Nothing is drawn beyond the columns' own draws, so every try is
## the same and the opening is what makes it fit (the fallback is that layout
## too).
static func _gen_columns(p: VariantParams, rocks: int) -> void:
	var a: Hazard
	var b: Hazard
	if rocks != BOTH:
		a = p.add(_fang(130, false, rocks == CEILING))
		b = p.add(_fang(230, true, rocks == CEILING))
	else:
		a = p.add(_stalactite(130 * SUB, false))
		b = p.add(_stalactite(230 * SUB, true))
	a.open_for_arrival(p.sim, p)
	b.open_for_arrival(p.sim, p)


## Generated Stalactite Run, alternating or short fangs: three columns round an
## open middle that stays put. The middle sits round the bird's hop where it
## came in (alternating within ALT_GEN_LO..ALT_GEN_HI, wider than the hand-made
## ALT_LO..ALT_HI; short fangs within SHORT_GEN_LO..SHORT_GEN_HI, where it was
## always SHORT_Y), and opens further for the arrival.
static func _gen_fixed(p: VariantParams, short: bool) -> void:
	var fingers: Array[Hazard] = []
	for i in 3:
		var f := _short(i) if short else _finger(i)
		f.fixed_lo = SHORT_GEN_LO if short else ALT_GEN_LO
		f.fixed_hi = SHORT_GEN_HI if short else ALT_GEN_HI
		fingers.append(p.add(f))
	for f in fingers:
		f.open_for_arrival(p.sim, p)


## Short fangs: column i of three, both rocks short.
static func _short(i: int) -> Hazard:
	var s := Stalactite.new(TRIO_X[i] * SUB, i > 0)
	s.gap = SHORT_GAP
	s.half_w = SHORT_HALF_W
	s.fixed_lo = SHORT_Y
	s.fixed_hi = SHORT_Y
	return s
