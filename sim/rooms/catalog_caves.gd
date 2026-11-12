extends RefCounted
## Cave Tunnel and Peg Field: rooms that only exist as recipes (GENERATED). Each
## is built once when the room starts, from the room RNG and the planned entry
## height (VariantParams), and never reshaped: only the declared moving parts
## move (drips, bats, the peg field's bob). Over the bird's 1 s hold out of a
## portal (the first GALLERY_X px from the wall it comes in at) nothing deadly
## is in the band it sweeps.

const CaveRock := preload("res://sim/hazards/cave_rock.gd")
const CaveDrip := preload("res://sim/hazards/cave_drip.gd")
const Mover := preload("res://sim/hazards/mover.gd")
const Peg := preload("res://sim/hazards/peg.gd")

const SUB := SimConfig.SUB
const W := SimConfig.WORLD_W

## Cave variants.
const FORK := 0
const DRIPS := 1
const BATS := 2

## How far from the wall the bird comes in at the hold band must stay clear
## (the bird's 1 s hold, its body included, and a little more).
const GALLERY_X := 272 * SUB
## The cave is checked within the exit's half height of the planned height,
## a little less than the whole exit (RoomVariant.arrival_spread).
const CAVE_SPREAD := SimConfig.EXIT_HALF
## The far end's bend (up to, per level 0, 1, 2+) and half height there.
const BEND: Array[int] = [40, 65, 90]
const BEND_HALF: Array[int] = [100, 95, 90]
## Fork: the island's tip, the two branches' half height at the far wall, and
## the island's half thickness there.
const ISLE_TIP_X := 300 * SUB
const BRANCH_HALF := 90 * SUB
const ISLE_HALF := 36 * SUB
## Rock: its lip sits FANG_ROOM_MIN..+FANG_ROOM_SPAN past the limit the fangs
## reach to; lip points every LIP_STEP; fangs every FANG_STEP..+FANG_STEP_SPAN,
## FANG_HALF..+FANG_HALF_SPAN wide each side; long points at LONG_TOP (ceiling)
## and LONG_BOTTOM (floor), entry-relative, reach the limit itself.
const FANG_ROOM_MIN := 22 * SUB
const FANG_ROOM_SPAN := 14 * SUB
const LIP_STEP := 12 * SUB
const FANG_STEP := 24 * SUB
const FANG_STEP_SPAN := 10 * SUB
const FANG_HALF := 6 * SUB
const FANG_HALF_SPAN := 5 * SUB
const LONG_HALF := 12 * SUB
const LONG_TOP: Array[int] = [55, 115, 175, 235]
const LONG_BOTTOM: Array[int] = [85, 145, 205]
## Drips: steps between drips (per level), and the first one's earliest step.
const DRIP_CADENCE: Array[int] = [72, 54, 36]
const DRIP_FIRST := 90
## Bats: each swoops up and down at its own spot (entry-relative px, per
## level), sways BAT_SWAY, takes BAT_PERIOD steps per figure-eight (two
## swoops). The gallery is BAT_ROOM taller each side, so a bat at the top or
## bottom of its swoop is clear of the arrival band.
const BAT_XS: Array[Array] = [[110, 210], [110, 210], [70, 150, 230]]
const BAT_SWAY := 6 * SUB
const BAT_PERIOD: Array[int] = [480, 420, 360]
const BAT_ROOM := 48 * SUB
## A bat keeps this much more than the two radii from the bird out of a portal.
const BAT_MARGIN := 4 * SUB

## Peg Field: pegs per level (as many as fit), their spacing (centre to
## centre: one hop plus the bird between the tips), the clear strip by the far
## wall, the field's margins, the drift's bob and the draws per layout.
const PEG_COUNT: Array[int] = [6, 8, 10]
const PEG_APART := 128 * SUB
const PEG_STRIP := 70 * SUB
const PEG_WALL := 24 * SUB
const PEG_EDGE := 10 * SUB
const PEG_BOB := 20 * SUB
const PEG_DRAWS := 80
## The limits the cave's fangs reach to (entry-relative x), as one array:
## L_TOP0, L_BOTTOM0 over the gallery, L_TOP1, L_BOTTOM1 at the far wall (a
## smooth bend between), and for a fork the island's tip height L_TIP and its
## edges at the far wall L_ISLE_TOP1, L_ISLE_BOTTOM1 (L_FORK 1).
const L_TOP0 := 0
const L_BOTTOM0 := 1
const L_TOP1 := 2
const L_BOTTOM1 := 3
const L_FORK := 4
const L_TIP := 5
const L_ISLE_TOP1 := 6
const L_ISLE_BOTTOM1 := 7


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Cave Tunnel: rock above and below leaves one tunnel: a gallery round the
	# arrival band, then a bend to the far wall. Fork: an island splits the
	# bend into two branches, the exit at the end of one. Drips: the long
	# points drip on a timetable, each with a glint first. Bats: bats loop
	# through the gallery. Checked within CAVE_SPREAD, a little less than the
	# whole exit (the user allowed the cave to be that much tighter).
	var cave := RoomDef.new("cave", "mid", 40)
	cave.max_spikes = 4
	cave.variants = [
		RoomVariant.new("fork").generated(_gen_cave.bind(FORK)).checked_within(CAVE_SPREAD),
		RoomVariant.new("drips").generated(_gen_cave.bind(DRIPS)).checked_within(CAVE_SPREAD),
		RoomVariant.new("bats").generated(_gen_cave.bind(BATS)).checked_within(CAVE_SPREAD),
	]
	out.append(cave)

	# Peg Field: round spiked pegs at fixed places, a hop and the bird apart,
	# clear of the arrival band and of a strip by the far wall. Drift: the
	# whole field bobs slowly together.
	var pegs := RoomDef.new("pegs", "mid", 30)
	pegs.max_spikes = 5
	pegs.variants = [
		RoomVariant.new("classic").generated(_gen_pegs.bind(false)),
		RoomVariant.new("drift").generated(_gen_pegs.bind(true)),
	]
	out.append(pegs)
	return out


## `x` (sub-units, from the wall the bird comes in at) from the left wall.
static func _x(p: VariantParams, x: int) -> int:
	return W - x if _flip(p) else x


## Whether the layout is mirrored: out of a portal in the right wall.
static func _flip(p: VariantParams) -> bool:
	return p.arriving and p.sim.state.vx < 0


## Integer smoothstep of `num` / `den` (clamped), scaled to `den`.
static func _smooth(num: int, den: int) -> int:
	var t := clampi(num, 0, den)
	return t * t / den * (3 * den - 2 * t) / den


static func _level(p: VariantParams) -> int:
	return mini(p.level, 2)


## The cave's arrival band (CAVE_SPREAD round the planned height), [top, bottom].
static func _cave_band(p: VariantParams) -> PackedInt32Array:
	var r := SimConfig.BIRD_RADIUS + VariantParams.MARGIN
	var spread := CAVE_SPREAD
	var high := GameSim._arrival_y(p.entry_y - spread)
	var low := GameSim._arrival_y(p.entry_y + spread)
	return PackedInt32Array([high - FairLanes.FIRST_HOP - r, low + r])


static func _limits(p: VariantParams, variant: int) -> PackedInt32Array:
	var lim := PackedInt32Array()
	lim.resize(8)
	var band := _cave_band(p)
	var room := BAT_ROOM if variant == BATS else 0
	lim[L_TOP0] = band[0] - room
	lim[L_BOTTOM0] = band[1] + room
	var c0 := (band[0] + band[1]) / 2
	var lv := _level(p)
	if variant == FORK:
		var outer := 2 * BRANCH_HALF + ISLE_HALF
		var m := clampi(c0, SimConfig.KILL_TOP + outer, SimConfig.KILL_BOTTOM - outer)
		lim[L_FORK] = 1
		lim[L_TIP] = c0
		lim[L_TOP1] = m - 2 * BRANCH_HALF - ISLE_HALF
		lim[L_BOTTOM1] = m + 2 * BRANCH_HALF + ISLE_HALF
		lim[L_ISLE_TOP1] = m - ISLE_HALF
		lim[L_ISLE_BOTTOM1] = m + ISLE_HALF
		return lim
	var half: int = BEND_HALF[lv] * SUB
	var bend: int = BEND[lv] * SUB
	var lo := SimConfig.KILL_TOP + half + 24 * SUB
	var hi := SimConfig.KILL_BOTTOM - half - 24 * SUB
	var c1 := clampi(c0 - bend + p.rng.next_below(2 * bend + 1), lo, hi)
	lim[L_TOP1] = c1 - half
	lim[L_BOTTOM1] = c1 + half
	return lim


## Limit `which` (0 tunnel top, 1 tunnel bottom, 2 island top, 3 island bottom)
## at entry-relative x.
static func _limit(lim: PackedInt32Array, which: int, x: int) -> int:
	if which < 2:
		var s := _smooth(x - GALLERY_X, W - GALLERY_X)
		var a := lim[L_TOP0 + which]
		return a + (lim[L_TOP1 + which] - a) * s / (W - GALLERY_X)
	var t := _smooth(x - ISLE_TIP_X, W - ISLE_TIP_X)
	var tip := lim[L_TIP]
	return tip + (lim[L_ISLE_TOP1 + which - 2] - tip) * t / (W - ISLE_TIP_X)


## One rock face as a polyline (entry-relative x, left to right): its lip
## FANG_ROOM past the limit `which` (0 tunnel top, 1 tunnel bottom, 2 island
## top, 3 island bottom), with fangs reaching toward the limit and the long
## points `longs` (px) reaching it. `rock_up`: rock is above the polyline.
static func _face(
	p: VariantParams, lim: PackedInt32Array, which: int, from_x: int, longs: Array[int]
) -> PackedInt32Array:
	var rock_up := which == 0 or which == 3
	var sign := -1 if rock_up else 1
	# The lip, every LIP_STEP. The island's lip is its limit: a smooth rock
	# with no fangs, so it can come to a point at its tip.
	var isle := which >= 2
	var lip_x := PackedInt32Array()
	var lip_y := PackedInt32Array()
	var x := from_x
	while true:
		var off := 0 if isle else FANG_ROOM_MIN + p.rng.next_below(FANG_ROOM_SPAN + 1)
		lip_x.append(x)
		lip_y.append(_limit(lim, which, x) + sign * off)
		if x >= W:
			break
		x = mini(x + LIP_STEP, W)
	# Fangs: the long ones first, then the rest where they fit.
	var fangs: Array[PackedInt32Array] = []
	for lx in longs:
		var cx := lx * SUB
		if cx - LONG_HALF > from_x:
			fangs.append(PackedInt32Array([cx, LONG_HALF, 1000]))
	x = from_x + FANG_STEP / 2 + p.rng.next_below(FANG_STEP_SPAN + 1)
	while not isle and x < W - FANG_STEP / 2:
		var half := FANG_HALF + p.rng.next_below(FANG_HALF_SPAN + 1)
		var reach := 350 + p.rng.next_below(551)
		var free := true
		for f in fangs:
			if absi(f[0] - x) < f[1] + half + 2 * SUB:
				free = false
		if free:
			fangs.append(PackedInt32Array([x, half, reach]))
		x += FANG_STEP + p.rng.next_below(FANG_STEP_SPAN + 1)
	fangs.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a[0] < b[0])
	# Merge: lip points outside every fang, and each fang's three points.
	var out_x := PackedInt32Array()
	var out_y := PackedInt32Array()
	var fi := 0
	for i in lip_x.size():
		var lx := lip_x[i]
		while fi < fangs.size() and fangs[fi][0] + fangs[fi][1] < lx:
			_add_fang(out_x, out_y, lip_x, lip_y, lim, which, fangs[fi])
			fi += 1
		var inside := false
		for f in fangs:
			if absi(f[0] - lx) <= f[1]:
				inside = true
		if not inside:
			out_x.append(lx)
			out_y.append(lip_y[i])
	while fi < fangs.size():
		_add_fang(out_x, out_y, lip_x, lip_y, lim, which, fangs[fi])
		fi += 1
	var out := PackedInt32Array()
	for i in out_x.size():
		out.append(out_x[i])
		out.append(out_y[i])
	return out


## Appends fang `f` (centre, half width, reach in thousandths of the room to
## the limit; 1000 = a long point) as its three points.
static func _add_fang(
	xs: PackedInt32Array,
	ys: PackedInt32Array,
	lip_x: PackedInt32Array,
	lip_y: PackedInt32Array,
	lim: PackedInt32Array,
	which: int,
	f: PackedInt32Array
) -> void:
	var x0 := f[0] - f[1]
	var x1 := f[0] + f[1]
	var y0 := CaveRock.edge_at(lip_x, lip_y, x0)
	var y1 := CaveRock.edge_at(lip_x, lip_y, x1)
	var base := (y0 + y1) / 2
	var to := _limit(lim, which, f[0])
	xs.append(x0)
	ys.append(y0)
	xs.append(f[0])
	ys.append(base + (to - base) * f[2] / 1000)
	xs.append(x1)
	ys.append(y1)


## Splits pairs [x, y, x, y...] into the rock's x and y arrays, entry-relative x
## turned into room x (mirrored, and reversed so x still grows, when the bird
## comes in from the right).
static func _store(p: VariantParams, pairs: PackedInt32Array) -> Array[PackedInt32Array]:
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var n := pairs.size() / 2
	for i in n:
		var j := n - 1 - i if _flip(p) else i
		xs.append(_x(p, pairs[2 * j]))
		ys.append(pairs[2 * j + 1])
	var out: Array[PackedInt32Array] = [xs, ys]
	return out


## Generated Cave Tunnel (FORK, DRIPS or BATS).
static func _gen_cave(p: VariantParams, variant: int) -> void:
	var lim := _limits(p, variant)
	var rock := CaveRock.new()
	var top := _store(p, _face(p, lim, 0, 0, LONG_TOP))
	var bottom := _store(p, _face(p, lim, 1, 0, LONG_BOTTOM))
	rock.top_x = top[0]
	rock.top_y = top[1]
	rock.bot_x = bottom[0]
	rock.bot_y = bottom[1]
	if variant == FORK:
		var none: Array[int] = []
		var upper := _face(p, lim, 2, ISLE_TIP_X, none)
		var lower := _face(p, lim, 3, ISLE_TIP_X, none)
		_store_isle(p, rock, upper, lower)
	p.add(rock)
	if variant == DRIPS:
		_add_drips(p, rock)
	elif variant == BATS:
		_add_bats(p, lim)


## Bats: one swooping bat per spot, each swoop nearly the gallery's height.
## Out of a portal each bat's timing is moved, once, to the first where it is
## above or below the arrival band whenever the bird flies past it during
## the hold (_bat_clear).
static func _add_bats(p: VariantParams, lim: PackedInt32Array) -> void:
	var lv := _level(p)
	var band := _cave_band(p)
	var mid := (lim[L_TOP0] + lim[L_BOTTOM0]) / 2
	var swing := (lim[L_BOTTOM0] - lim[L_TOP0]) / 2 - Mover.RADIUS - BAT_MARGIN
	for bx: int in BAT_XS[lv]:
		var bat := Mover.new("figure8", 1)
		bat.loop_w = BAT_SWAY
		bat.loop_h = swing
		bat.loop_period = BAT_PERIOD[lv]
		bat.center_x = _x(p, bx * SUB)
		bat.center_y = mid
		p.add(bat)
		if not p.arriving:
			continue
		var start: int = bat.phase
		for d in bat.period():
			bat.phase = (start + d) % bat.period()
			if _bat_clear(p, bat, band):
				break
		bat._place()


## Whether `bat` stays off the arrival band whenever it is near the bird's
## x during the hold (VariantCheck.HOLD_STEPS).
static func _bat_clear(p: VariantParams, bat: Mover, band: PackedInt32Array) -> bool:
	var reach := SimConfig.BIRD_RADIUS + Mover.RADIUS + BAT_MARGIN
	var keep := bat.t
	var clear := true
	for k in range(1, VariantCheck.HOLD_STEPS + 1):
		bat.t = k
		bat._place()
		if absi(bat.xs[0] - FairLanes.arrival_x(p.sim, k)) >= reach:
			continue
		if (
			bat.ys[0] + Mover.RADIUS + BAT_MARGIN > band[0]
			and bat.ys[0] - Mover.RADIUS - BAT_MARGIN < band[1]
		):
			clear = false
			break
	bat.t = keep
	return clear


## The island: its two faces sampled at the same x's (the upper face's, past
## the tip), so the rock between them is one shape.
static func _store_isle(
	p: VariantParams, rock: CaveRock, upper: PackedInt32Array, lower: PackedInt32Array
) -> void:
	var lx := PackedInt32Array()
	var ly := PackedInt32Array()
	for i in lower.size() / 2:
		lx.append(lower[2 * i])
		ly.append(lower[2 * i + 1])
	var pairs := PackedInt32Array()
	var bottoms := PackedInt32Array()
	for i in upper.size() / 2:
		var x := upper[2 * i]
		pairs.append(x)
		pairs.append(upper[2 * i + 1])
		bottoms.append(maxi(CaveRock.edge_at(lx, ly, x), upper[2 * i + 1]))
	var top := _store(p, pairs)
	var bot_pairs := PackedInt32Array()
	for i in bottoms.size():
		bot_pairs.append(upper[2 * i])
		bot_pairs.append(bottoms[i])
	var bottom := _store(p, bot_pairs)
	rock.isle_x = top[0]
	rock.isle_top = top[1]
	rock.isle_bot = bottom[1]


## Drips from the ceiling's long points: one every DRIP_CADENCE steps, the
## points in an order drawn now, the first after DRIP_FIRST.
static func _add_drips(p: VariantParams, rock: CaveRock) -> void:
	var lv := _level(p)
	var cadence: int = DRIP_CADENCE[lv]
	var n := LONG_TOP.size()
	var order: Array[int] = []
	for i in n:
		order.append(i)
	for i in range(n - 1, 0, -1):
		var j := p.rng.next_below(i + 1)
		var keep := order[i]
		order[i] = order[j]
		order[j] = keep
	var first := DRIP_FIRST + p.rng.next_below(cadence)
	var drips: Array[CaveDrip] = []
	var longest := 0
	for k in n:
		var x := _x(p, LONG_TOP[order[k]] * SUB)
		var tip := CaveRock.edge_at(rock.top_x, rock.top_y, x)
		var floor_y := CaveRock.edge_at(rock.bot_x, rock.bot_y, x)
		var d := CaveDrip.new(x, tip, floor_y, first + k * cadence, 1)
		longest = maxi(longest, d.fall_steps())
		drips.append(d)
	var every := maxi(n * cadence, longest + CaveDrip.GLINT + 12)
	for d in drips:
		d.every = every
		p.add(d)


## Generated Peg Field: up to PEG_COUNT pegs drawn one at a time, each kept
## only where it leaves the arrival band clear over the hold, the far strip
## clear and the others PEG_APART away. Drift: the field bobs together.
static func _gen_pegs(p: VariantParams, drift: bool) -> void:
	var bob := PEG_BOB if drift else 0
	var phase := p.rng.next_below(Peg.BOB_PERIOD) if drift else 0
	var r := Peg.RADIUS + bob
	var top := p.hold_top()
	var bottom := p.hold_bottom()
	var want: int = PEG_COUNT[_level(p)]
	var made: Array[PackedInt32Array] = []
	var lo_x := PEG_WALL + Peg.RADIUS
	var hi_x := W - PEG_STRIP - Peg.RADIUS
	var lo_y := SimConfig.KILL_TOP + PEG_EDGE + r
	var hi_y := SimConfig.KILL_BOTTOM - PEG_EDGE - r
	for k in PEG_DRAWS:
		if made.size() >= want:
			break
		var x := lo_x + p.rng.next_below(hi_x - lo_x + 1)
		var y := lo_y + p.rng.next_below(hi_y - lo_y + 1)
		if x < GALLERY_X + Peg.RADIUS and y + r > top and y - r < bottom:
			continue
		var apart := true
		for q in made:
			var dx := q[0] - x
			var dy := q[1] - y
			if dx * dx + dy * dy < PEG_APART * PEG_APART:
				apart = false
		if apart:
			made.append(PackedInt32Array([x, y]))
	for q in made:
		p.add(Peg.new(_x(p, q[0]), q[1], bob, phase))
