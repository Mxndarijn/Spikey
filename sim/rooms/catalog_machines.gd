extends RefCounted
## Rooms batch: machines. Order is part of the rules (see RoomCatalog).

const Piston := preload("res://sim/hazards/piston.gd")
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
## Short fangs: a 300 px corridor round the middle, thinner rocks; out of a
## portal only where a bird holding its height stays inside it.
const SHORT_GAP := 300 * SUB
const SHORT_Y := 320 * SUB
const SHORT_HALF_W := 18 * SUB
## Generated Stalactite Run: the entry column stands here, its gap still and
## wide enough for the band a bird holding its height anywhere in the exit
## sweeps (GEN_SLACK more each side); the far column, scheduled, stands past
## that band's reach (the bird gets to it just after its 1 s hold) and out of
## the exit's mouth (ExitZone.DEPTH from the wall).
const ENTRY_X := 110 * SUB
const FAR_X := 292 * SUB
const GEN_SLACK := 4 * SUB
const ENTRY_GAP := (
	2 * SimConfig.EXIT_FIT
	+ FairLanes.FIRST_HOP
	+ 2 * (SimConfig.BIRD_RADIUS + VariantParams.MARGIN)
	+ 2 * GEN_SLACK
)


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

	# Stalactite Run: rock columns with a gap. Every variant is GENERATED and
	# keeps one layout all room, never reading the bird. Classic: a wide still
	# column near the entry round the band a bird holding its height anywhere in
	# the exit sweeps, then a far column whose 150 px gap slides to a new
	# height each time the bird bounces off the left wall, on a list drawn when
	# the room starts (it parks on the exit's lane before the exit opens).
	# Floor fangs / ceiling only: the same, with only the rocks from the floor /
	# the ceiling. Alternating: three still fingers, hanging, standing,
	# hanging; the first two clear of that band, the last one past it. Short
	# fangs: three short columns round a 300 px corridor on that band.
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


## Crate Drop's variants; Winter Gift Stack has the same ones with gifts. All
## GENERATED: crates drop from the ceiling, so out of a portal the columns are
## drawn again until the first crates miss a bird holding its height for
## FairLanes.ARRIVAL_PATH_TICKS (the first one falls after the reading time).
static func crate_variants(gifts: bool) -> Array[RoomVariant]:
	var shapes := [["classic", false, false], ["wide", true, false], ["pairs", false, true]]
	var out: Array[RoomVariant] = []
	for sh: Array in shapes:
		var v := RoomVariant.new(sh[0])
		v.generated(_gen_crates.bind(gifts, sh[1], sh[2]), false, FairLanes.ARRIVAL_PATH_TICKS)
		out.append(v)
	return out


## Generated Crate Drop / Gift Stack: the crates as hand made (they draw their
## columns). The fallback holds the first crate back for the arrival path's
## length more, its column marked all that time (the first crate is picked on
## the room's first step: its warning is still to come, CrateDrop.WAIT).
static func _gen_crates(p: VariantParams, gifts: bool, wide: bool, pair: bool) -> void:
	var c: Hazard = p.add(_crates(gifts, wide, pair))
	if p.fallback and p.arriving:
		if c.col == CrateDrop.WAIT:
			c.wait_warn += FairLanes.ARRIVAL_PATH_TICKS
		else:
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


static func _stalactite(x: int, follows: bool) -> Hazard:
	return Stalactite.new(x, follows)


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
## only: a wide still entry column round the hold band (_still), then a far
## column with the variant's own gap that slides on a schedule drawn now
## (Stalactite.scheduled). The layout never reads the bird.
static func _gen_columns(p: VariantParams, rocks: int) -> void:
	var entry := _from_entry(p, ENTRY_X)
	var far := _from_entry(p, FAR_X)
	var a: Hazard = _stalactite(entry, false) if rocks == BOTH else _fang_at(entry, rocks)
	p.add(_still(a, p, ENTRY_GAP))
	var b: Hazard = _stalactite(far, false) if rocks == BOTH else _fang_at(far, rocks)
	b.scheduled = true
	p.add(b)


## `x` (sub-units, from the left wall) measured from the wall a bird out of a
## portal comes in at instead.
static func _from_entry(p: VariantParams, x: int) -> int:
	return SimConfig.WORLD_W - x if p.arriving and p.sim.state.vx < 0 else x


## A floor fang or ceiling rock at x (sub-units), leading.
static func _fang_at(x: int, rocks: int) -> Hazard:
	var s := Stalactite.new(x, false)
	s.top = rocks == CEILING
	s.bottom = rocks != CEILING
	s.gap = Stalactite.GAP if rocks == CEILING else FANG_GAP
	return s


## Makes `s` a still column whose gap (`gap` tall) is centred on the band a bird
## holding its height anywhere in the exit sweeps. Before setup.
static func _still(s: Hazard, p: VariantParams, gap: int) -> Hazard:
	var mid := (p.hold_top() + p.hold_bottom()) / 2
	s.gap = gap
	s.fixed_lo = mid
	s.fixed_hi = mid
	return s


## Generated Stalactite Run, alternating or short fangs: three still columns.
## Alternating: the first two fingers keep the hold band clear (ENTRY_GAP) and
## the last one, moved out to FAR_X, hangs ALT_GAP / 2 over the band's middle.
## Short fangs: the 300 px corridor holds the band, centred on it.
static func _gen_fixed(p: VariantParams, short: bool) -> void:
	for i in 3:
		var f := _short(i) if short else _finger(i)
		f.x = _from_entry(p, f.x if i < 2 or short else FAR_X)
		if short:
			_still(f, p, SHORT_GAP)
		elif i < 2:
			_still(f, p, ENTRY_GAP)
		else:
			_still(f, p, ALT_GAP)
		p.add(f)


## Short fangs: column i of three, both rocks short.
static func _short(i: int) -> Hazard:
	var s := Stalactite.new(TRIO_X[i] * SUB, i > 0)
	s.gap = SHORT_GAP
	s.half_w = SHORT_HALF_W
	s.fixed_lo = SHORT_Y
	s.fixed_hi = SHORT_Y
	return s
