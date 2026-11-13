extends RefCounted
## Rooms batch: machines. Order is part of the rules (see RoomCatalog).

const Piston := preload("res://sim/hazards/piston.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const Stalactite := preload("res://sim/hazards/stalactite.gd")
const Dart := preload("res://sim/hazards/dart.gd")

const SUB := SimConfig.SUB

## Generated Piston Press: how many rams (PRESS_MIN, one more from
## PRESS_MORE_AT points), the least room between two rows (centre to centre:
## PRESS_ROW_GAP_FEW for three rams, a 74 px gap, more than a hop; 48 px for
## four), at most PRESS_MAX_RIGHT in the right
## wall (the exits' wall), the reach (PRESS_REACH_MIN plus up to
## PRESS_REACH_STEPS - 1 steps), the warning (PRESS_GLOW, PRESS_GLOW_STEP
## shorter per level, never under today's Piston.GLOW_TICKS), the first ram's
## wait and the beat between rams in a wave.
const PRESS_MIN := 3
const PRESS_MORE_AT := 100
const PRESS_ROW_GAP := 84 * SUB
const PRESS_ROW_GAP_FEW := 110 * SUB
## The rows' range (centres): far enough from the ceiling and floor that a
## bird above the top ram or under the bottom one still has a hop's room.
const PRESS_TOP := 150 * SUB
const PRESS_BOTTOM := 490 * SUB
const PRESS_MAX_RIGHT := 2
const PRESS_REACH_MIN := 120 * SUB
const PRESS_REACH_STEP := 20 * SUB
const PRESS_REACH_STEPS := 4
const PRESS_GLOW := 44
const PRESS_GLOW_STEP := 6
const PRESS_DELAY := 30
const PRESS_BEAT_MIN := 24
const PRESS_BEAT_SPAN := 24
## Rhythms: a wave top to bottom or bottom to top, every other ram half a cycle
## apart, or each ram at a drawn place in the cycle.
const WAVE_DOWN := 0
const WAVE_UP := 1
const HALVES := 2
const SCATTER := 3
## Generated Beam Gates (_gen_beams). Each row is drawn in its own band
## (Beam.BAND_TOP + i * 120 px, plus up to Beam.JITTER) and then moved, by as
## little as it takes (BEAM_STEP at a time, up to BEAM_SHIFT), until its live
## core clears every planned exit's mouth by BEAM_EXIT_CLEAR (a bird inside the
## mouth never meets a beam), staying BEAM_APART from the row above and inside
## BEAM_TOP..BEAM_BOTTOM. A row that can't is left out.
const BEAM_STEP := 4 * SUB
const BEAM_SHIFT := 60 * SUB
const BEAM_APART := 80 * SUB
const BEAM_TOP := 110 * SUB
const BEAM_BOTTOM := 540 * SUB
const BEAM_EXIT_CLEAR := SimConfig.EXIT_HALF + Beam.HALF_H
## The beat's places tried (steps apart) when it is timed to the exit, the
## heights a bird is tried from (apart) and how late it may start.
const BEAM_PHASE_STEP := 5
const BEAM_START_STEP := 20 * SUB
const BEAM_LATE := 20
## Spikes a wall keeps at most once the exit's ghost shows (the room's walls have
## up to seven before that).
const BEAM_CALM_SPIKES := 5
## A bird in the mouth: its centre within this of the exit's height.
const BEAM_LANE := SimConfig.EXIT_HALF - SimConfig.BIRD_RADIUS
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
## The far column's gap (both rocks, or a hanging one): the bird meets it a few
## steps after its 1 s hold out of a portal, so it is wide enough to steer into
## from anywhere in the exit by then.
const FAR_GAP := 200 * SUB
const GEN_SLACK := 4 * SUB
const ENTRY_GAP := (
	2 * SimConfig.EXIT_FIT
	+ FairLanes.FIRST_HOP
	+ 2 * (SimConfig.BIRD_RADIUS + VariantParams.MARGIN)
	+ 2 * GEN_SLACK
)


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Piston Press: rams mark their lane, slam across part of the room, hold
	# and pull back. One GENERATED layout (_gen_press): the rams' rows, walls,
	# reach and rhythm are drawn when the room starts and never change.
	var piston := RoomDef.new("piston", "mid", 30)
	piston.max_spikes = 6
	piston.variants = [RoomVariant.new("generated").generated(_gen_press)]
	out.append(piston)

	# Crate Drop: crates fall one at a time and pile up in columns (classic),
	# or big crates make fat towers (wide), or two fall at once (pairs).
	var crates := RoomDef.new("crates", "mid", 60)
	crates.max_spikes = 6
	crates.variants = crate_variants(false)
	out.append(crates)

	# Beam Gates: four wall-to-wall beams firing in turn, each warned 2 s first.
	# One GENERATED layout (_gen_beams): the rows and their firing order are
	# drawn when the room starts, around the room's planned exits, and never
	# change. Seven spikes a wall, five from the exit's ghost on (BEAM_CALM_SPIKES),
	# keep it as hard as the hand-made room was.
	var beams := RoomDef.new("beams", "mid", 50)
	beams.max_spikes = 7
	beams.variants = [RoomVariant.new("generated").generated(_gen_beams)]
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


## Twin hunters: dart `slot` fires from wall `home`.
static func _hunter(slot: int, home: int) -> Hazard:
	return Dart.new(false, slot, home)


## Generated Piston Press: PRESS_MIN or PRESS_MIN + 1 rams in rows at least
## PRESS_ROW_GAP_FEW or PRESS_ROW_GAP apart between PRESS_TOP and PRESS_BOTTOM (slack drawn per
## row), each in a drawn wall (both walls get one, the right at most
## PRESS_MAX_RIGHT) with a drawn reach, all with one warning and one drawn
## rhythm. Built from the room's draws and the score only, never the bird. The
## fallback leaves out the rams whose row crosses the band a bird holding its
## height out of the exit sweeps.
static func _gen_press(p: VariantParams) -> void:
	var n := PRESS_MIN + (1 if p.score >= PRESS_MORE_AT else 0)
	var gap := PRESS_ROW_GAP_FEW if n == PRESS_MIN else PRESS_ROW_GAP
	var slack := PRESS_BOTTOM - PRESS_TOP - (n - 1) * gap
	var offs: Array[int] = []
	for i in n:
		offs.append(p.rng.next_below(slack + 1))
	offs.sort()
	var glow := maxi(Piston.GLOW_TICKS, PRESS_GLOW - p.level * PRESS_GLOW_STEP)
	var rhythm := p.rng.next_below(4)
	var beat := PRESS_BEAT_MIN + p.rng.next_below(PRESS_BEAT_SPAN + 1)
	var period := (
		Piston.IDLE_TICKS + glow + Piston.EXTEND_TICKS + Piston.HOLD_TICKS + Piston.RETRACT_TICKS
	)
	var rams: Array[Piston] = []
	var rights := 0
	for i in n:
		var side := p.rng.next_below(2)
		if side == 1 and rights >= PRESS_MAX_RIGHT:
			side = 0
		rights += side
		var reach := PRESS_REACH_MIN + p.rng.next_below(PRESS_REACH_STEPS) * PRESS_REACH_STEP
		var at := p.rng.next_below(period)
		var delay := PRESS_DELAY
		match rhythm:
			WAVE_DOWN:
				delay += i * beat
			WAVE_UP:
				delay += (n - 1 - i) * beat
			HALVES:
				delay += (i % 2) * (period / 2)
			_:
				delay += at
		rams.append(Piston.new(side, PRESS_TOP + i * gap + offs[i], delay, glow, reach))
	if rights == 0:
		rams[n / 2].side = 1
	for ram: Piston in rams:
		var crosses := (
			ram.y + Piston.HALF_H > p.hold_top() and ram.y - Piston.HALF_H < p.hold_bottom()
		)
		if p.fallback and p.arriving and crosses:
			continue
		p.add(ram)


## Generated Beam Gates: Beam.ROWS rows round the room's planned exits (both
## walls, both exits of a fork), from the room's draws, the seed's exit plan and
## nothing the player does. Draws: one jitter per row, then where to start in
## the list of firing orders. The beat keeps its 2 s warnings and its spacing;
## what is picked is its order and where it stands when the exit shows: the one
## (tried BEAM_PHASE_STEP apart) that gets a bird from anywhere in the cage into
## the exit's mouth quickest after the exit's ghost shows (_exit_times,
## Beam.reach_time). The fallback is the same layout (the arrival check never
## meets a live beam: the first fires after its 2 s warning).
static func _gen_beams(p: VariantParams) -> void:
	var exits := _planned_exits(p.sim)
	var rows: Array[int] = []
	for i in Beam.ROWS:
		var drawn := Beam.BAND_TOP + i * (Beam.SPAN / Beam.ROWS) + p.rng.next_below(Beam.JITTER + 1)
		var y := _beam_row(drawn, exits, rows)
		if y >= 0:
			rows.append(y)
	var s := p.sim.state
	var lanes: Array[int] = [s.plan_a_y_right]
	if s.plan_a_kind_right != SimState.ExitKind.NORMAL:
		lanes.append(s.plan_b_y_right)
	var times := _exit_times(p.sim)
	var first := p.rng.next_below(_orders(rows.size()).size())
	var best: Array[int] = _beam_beat(rows, lanes, times[0], first)[0]
	var b := Beam.new(rows.size())
	for i in rows.size():
		b.rows[i] = rows[i]
		b.delays[i] = best[i]
	b.preset = true
	b.exit_ys = lanes
	b.calm_spikes = BEAM_CALM_SPIKES
	p.add(b)


## The firing order and place in the beat (from `first` in the list of orders,
## tried BEAM_PHASE_STEP apart) that gets a bird into every lane quickest after
## `shown`: [its delays, the steps that takes].
static func _beam_beat(rows: Array[int], lanes: Array[int], shown: int, first: int) -> Array:
	var orders := _orders(rows.size())
	var stagger := Beam.PERIOD / Beam.ROWS
	var best: Array[int] = []
	var best_w := -1
	for k in orders.size():
		var order: Array[int] = orders[(first + k) % orders.size()]
		var ph := 0
		while ph < Beam.PERIOD:
			var delays: Array[int] = []
			for i in rows.size():
				delays.append(Beam.START_DELAY + (order[i] * stagger + ph) % Beam.PERIOD)
			var w := 0
			for e in lanes:
				w = maxi(w, _beam_reach(rows, delays, shown, e))
			if best_w < 0 or w < best_w:
				best = delays
				best_w = w
			ph += BEAM_PHASE_STEP
	return [best, best_w]


## The most steps a bird needs, once the exit's ghost shows at step `shown`,
## to get into the mouth of the exit at `e` (Beam.reach_time): from every
## height BEAM_START_STEP apart that no row covers, starting then or
## BEAM_LATE steps later (a bird still flying the other way, or slow to react).
static func _beam_reach(rows: Array[int], delays: Array[int], shown: int, e: int) -> int:
	var w := 0
	var y0 := SimConfig.KILL_TOP + SimConfig.BIRD_RADIUS
	while y0 <= SimConfig.KILL_BOTTOM - SimConfig.BIRD_RADIUS:
		var free := true
		for r in rows:
			if absi(y0 - r) < Beam.HALF_H + SimConfig.BIRD_RADIUS:
				free = false
		if free:
			for late: int in [0, BEAM_LATE]:
				var to := Beam.reach_time(
					rows, delays, y0, shown + late, e - BEAM_LANE, e + BEAM_LANE
				)
				w = maxi(w, late + to)
		y0 += BEAM_START_STEP
	return w


## Room steps from now until the exit's ghost shows and until the bird gets to
## the exit's wall once it is open. The bird flies across at one speed whatever
## the player does, every bounce scores (until the exit opens) and the exit is
## on SimConfig.EXIT_WALL, so both follow from the room's start.
static func _exit_times(sim: GameSim) -> Array[int]:
	var heading := 1 if sim.state.vx > 0 else 0
	var t1 := sim.steps_to_wall(heading)
	var c := sim.steps_to_wall(1 - heading) - t1
	var k_open := sim.next_exit_score() - sim.state.score
	# Bounce k (from 1) is off the wall the bird heads to now when k is odd.
	var open_side := heading if k_open % 2 == 1 else 1 - heading
	var k_arr := k_open + 2 if open_side == SimConfig.EXIT_WALL else k_open + 1
	var k_prev := maxi(1, k_open - 1)
	return [t1 + (k_prev - 1) * c, t1 + (k_arr - 1) * c]


## The room's planned exit heights (ExitPlanner.plan_room, from the room's seed
## and the exit score: the same plan the room makes once it has started).
static func _planned_exits(sim: GameSim) -> Array[int]:
	ExitPlanner.plan_room(sim, sim.next_exit_score())
	var s := sim.state
	var out: Array[int] = [s.plan_a_y_left, s.plan_a_y_right]
	if s.plan_a_kind_left != SimState.ExitKind.NORMAL:
		out.append(s.plan_b_y_left)
	if s.plan_a_kind_right != SimState.ExitKind.NORMAL:
		out.append(s.plan_b_y_right)
	return out


## Row height nearest `drawn` (tried BEAM_STEP apart, up first) whose core
## clears every exit's mouth, BEAM_APART below the rows placed so far and inside
## BEAM_TOP..BEAM_BOTTOM; -1 if none within BEAM_SHIFT.
static func _beam_row(drawn: int, exits: Array[int], placed: Array[int]) -> int:
	var d := 0
	while d <= BEAM_SHIFT:
		for y: int in [drawn - d, drawn + d]:
			if _beam_row_ok(y, exits, placed):
				return y
		d += BEAM_STEP
	return -1


static func _beam_row_ok(y: int, exits: Array[int], placed: Array[int]) -> bool:
	if y < BEAM_TOP or y > BEAM_BOTTOM:
		return false
	if not placed.is_empty() and y - placed[placed.size() - 1] < BEAM_APART:
		return false
	for e in exits:
		if absi(y - e) < BEAM_EXIT_CLEAR:
			return false
	return true


## Every order of `n` rows (order[i]: row i's place in the beat), in
## lexicographic order.
static func _orders(n: int) -> Array:
	var out: Array = []
	var cur: Array[int] = []
	_orders_from(n, cur, out)
	return out


static func _orders_from(n: int, cur: Array[int], out: Array) -> void:
	if cur.size() == n:
		out.append(cur.duplicate())
		return
	for v in n:
		if not cur.has(v):
			cur.append(v)
			_orders_from(n, cur, out)
			cur.pop_back()


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
	if rocks != FLOOR:
		b.gap = FAR_GAP
	b.scheduled = true
	b.start_y = (p.hold_top() + p.hold_bottom()) / 2
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
## the last one, moved out to FAR_X, too (the bird meets it as its hold ends).
## Short fangs: the 300 px corridor holds the band, centred on it.
static func _gen_fixed(p: VariantParams, short: bool) -> void:
	for i in 3:
		var f := _short(i) if short else _finger(i)
		f.x = _from_entry(p, f.x if i < 2 or short else FAR_X)
		if short:
			_still(f, p, SHORT_GAP)
		else:
			_still(f, p, ENTRY_GAP)
		p.add(f)


## Short fangs: column i of three, both rocks short.
static func _short(i: int) -> Hazard:
	var s := Stalactite.new(TRIO_X[i] * SUB, i > 0)
	s.gap = SHORT_GAP
	s.half_w = SHORT_HALF_W
	s.fixed_lo = SHORT_Y
	s.fixed_hi = SHORT_Y
	return s
