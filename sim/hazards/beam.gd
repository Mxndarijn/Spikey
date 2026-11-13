extends Hazard
## Beam Gates: ROWS (or fewer) pairs of wall emitters, each firing a full-width beam on its
## own beat. A dashed warning flickers before a beam turns on; live beams kill.
## Beams take turns (one starts every PERIOD / row count steps and each stays on for
## a little more than that), so at most two are on at once and the other rows
## are always open. A beam stops short of an open or ghost exit's mouth
## (ExitZone).

enum State { OFF, WARN, ON }

## Rows in the Beam Gates room.
const ROWS := 4
const PERIOD := 180
const WARN_TICKS := SimConfig.WARN_TICKS
const ON_TICKS := 50
## Quiet time after the room starts, before the first warning.
const START_DELAY := 20
## The rows share SPAN below BAND_TOP: row i sits in its own band, BAND_TOP +
## i * SPAN / row count, plus up to JITTER.
const BAND_TOP := 130 * SimConfig.SUB
const SPAN := 480 * SimConfig.SUB
const JITTER := 40 * SimConfig.SUB
## Half the thickness of a live beam's deadly core.
const HALF_H := 6 * SimConfig.SUB
## Skipping a turn (yields): a beam stays off if a hazard comes this close to
## its row, beyond the hazard's own size: room for the bird to pass between.
const YIELD_GAP := 2 * SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB
## ...from this many steps before the beam turns on until it turns off.
const YIELD_LEAD := 20
## adjust_wall: a bird at a free height of the wall it flies to must be clear
## of every live beam (by MARGIN) from WALL_FROM to WALL_TO steps around its
## arrival there (sampled every WALL_STEP).
const WALL_FROM := -6
const WALL_TO := 30
const WALL_STEP := 6
const MARGIN := 4 * SimConfig.SUB
## reach_time: how fast the bird it imagines climbs and drops (a step).
const REACH_UP := 2 * SimConfig.SUB
const REACH_DOWN := 4 * SimConfig.SUB
## adjust_wall: steps a bird getting from one wall's free run to the next keeps
## to spare.
const REACH_SPARE := 10

## Centre height of each row's beam.
var rows: Array[int] = []
## Steps before each row's first warning (its offset into the beat).
var delays: Array[int] = []
## Steps of dashed warning before a beam turns on.
var warn_ticks := WARN_TICKS
## Skip a row's turn when another hazard will be in that row while it is live
## (Double Trouble: no two dangers in one band at once).
var yields := false
## 1 while row i sits out its current turn.
var skip: Array[int] = []
## Rows and delays set before setup (a generated Beam Gates layout): setup
## draws nothing.
var preset := false
## Generated Beam Gates: the planned exit heights on SimConfig.EXIT_WALL, and how
## many spikes a wall the bird gets to once the exit's ghost shows keeps at most
## (0 = no limit): the ones nearest the exit's height go first (adjust_wall).
var exit_ys: Array[int] = []
var calm_spikes := 0


## `count` rows; fewer rows sit further apart (Double Trouble uses 3, so a
## second hazard always has room to dodge between them).
func _init(count: int = ROWS, p_warn: int = WARN_TICKS, p_yields: bool = false) -> void:
	kind = "beam"
	rows.resize(count)
	delays.resize(count)
	skip.resize(count)
	skip.fill(0)
	warn_ticks = p_warn
	yields = p_yields


func setup(_sim: GameSim, rng: SimRng) -> void:
	if preset:
		return
	var n := rows.size()
	var band := SPAN / n
	# One beam starts every `stagger` steps.
	var stagger := PERIOD / n
	var order: Array[int] = []
	for i in n:
		order.append(i)
	# Fisher-Yates: the order rows fire in.
	for i in range(n - 1, 0, -1):
		var j := rng.next_below(i + 1)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in n:
		rows[i] = BAND_TOP + i * band + rng.next_below(JITTER + 1)
		delays[i] = START_DELAY + order[i] * stagger


## Steps into row i's beat, or -1 before its first one.
func cycle_pos(i: int) -> int:
	if t < delays[i]:
		return -1
	return posmod(t - delays[i], PERIOD)


func state(i: int) -> State:
	var p := cycle_pos(i)
	if p < 0 or p >= warn_ticks + ON_TICKS or skip[i] == 1:
		return State.OFF
	return State.WARN if p < warn_ticks else State.ON


## At the start of each row's turn, check whether it has to sit this one out.
func step(sim: GameSim) -> void:
	if not yields:
		return
	for i in rows.size():
		if cycle_pos(i) != 0:
			continue
		skip[i] = 0
		for h: Hazard in sim.room.hazards:
			if h == self or not h.alive:
				continue
			var half := HALF_H + YIELD_GAP
			if h.near_row(sim, rows[i], half, warn_ticks - YIELD_LEAD, warn_ticks + ON_TICKS):
				skip[i] = 1


## 0..1024 how far into the warning (0 outside it).
func warn_progress(i: int) -> int:
	if state(i) != State.WARN:
		return 0
	return SimTrig.ONE * cycle_pos(i) / warn_ticks


func live_count() -> int:
	var n := 0
	for i in rows.size():
		if state(i) == State.ON:
			n += 1
	return n


## Where row i's beam starts (left end); it stops short of an exit's mouth
## (ExitZone) on the left wall it would cross.
func beam_left(sim: GameSim, i: int) -> int:
	if _crosses_exit(sim, i, 0):
		return ExitZone.right_on(sim, 0) + 1
	return sim.room.wall_left()


## Where row i's beam ends (right end), short of a mouth on the right wall.
func beam_right(sim: GameSim, i: int) -> int:
	if _crosses_exit(sim, i, 1):
		return ExitZone.left_on(sim, 1) - 1
	return sim.room.wall_right()


func _crosses_exit(sim: GameSim, i: int, side: int) -> bool:
	return ExitZone.hits_rect_on(
		sim, side, sim.room.wall_left(), rows[i] - HALF_H, sim.room.wall_right(), rows[i] + HALF_H
	)


## True if row i's beam is live `steps` from now (a turn it might sit out
## counts as live).
func live_in(i: int, steps: int) -> bool:
	var at := t + steps
	if at < delays[i]:
		return false
	var p := posmod(at - delays[i], PERIOD)
	return p >= warn_ticks and p < warn_ticks + ON_TICKS


## Steps a bird at height y at step 	 needs to get into the heights lo..hi
## (its centre) through rows p_rows firing on p_delays: a simple flight,
## down REACH_DOWN and up REACH_UP a step, waiting beside each row in the way
## while it is live; a row is crossed while its core stays off for the whole
## time the bird overlaps it (a warning is only a warning). For the Beam Gates
## generator: no draws.
static func reach_time(
	p_rows: Array[int], p_delays: Array[int], y: int, t: int, lo: int, hi: int
) -> int:
	if y >= lo and y <= hi:
		return 0
	var t0 := t
	var down := y < lo
	var target := lo if down else hi
	var speed := REACH_DOWN if down else REACH_UP
	var reach := HALF_H + SimConfig.BIRD_RADIUS
	var order: Array[int] = []
	for i in p_rows.size():
		var r := p_rows[i]
		if (down and r > y and r < target) or (not down and r < y and r > target):
			order.append(i)
	if not down:
		order.reverse()
	var at := y
	for i in order:
		var near := p_rows[i] - reach if down else p_rows[i] + reach
		t += absi(near - at) / speed
		var cross := 2 * reach / speed
		t += _wait_off(p_delays[i], t, cross)
		t += cross
		at = p_rows[i] + reach if down else p_rows[i] - reach
	t += absi(target - at) / speed
	return t - t0


## Slots of wall `side` (drawn now, met after the other wall) a bird gets to in
## time from every free slot of the other wall (reach_time, REACH_SPARE steps to
## spare); every slot if the bird meets `side` first. No draws.
func reachable_slots(sim: GameSim, side: int) -> int:
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	var heading := 1 if sim.state.vx > 0 else 0
	if heading == side:
		return all
	var first := sim.steps_to_wall(heading)
	var c := sim.steps_to_wall(side) - first
	var other := sim.state.left_spikes if heading == 0 else sim.state.right_spikes
	var t_b := t + first
	var half := SimConfig.SLOT_SIZE / 2
	var out := 0
	for slot in SimConfig.SLOT_COUNT:
		var cy := SimConfig.slot_center_y(slot)
		var ok := true
		for from in SimConfig.SLOT_COUNT:
			if RoomRules.has_slot(other, from):
				continue
			var to := reach_time(
				rows, delays, SimConfig.slot_center_y(from), t_b, cy - half, cy + half
			)
			if to > c - REACH_SPARE:
				ok = false
				break
		if ok:
			out |= 1 << slot
	return out


## Steps to wait from `t` until a row on delay `d` stays off `len` steps.
static func _wait_off(d: int, t: int, length: int) -> int:
	var q := posmod(t - d - WARN_TICKS, PERIOD)
	if q < ON_TICKS:
		return ON_TICKS - q
	if q + length > PERIOD:
		return PERIOD - q + ON_TICKS
	return 0


## Keeps a way past the beams on the wall the bird flies to: a free run as wide
## as the room's gap (or the widest the beams leave) whose heights no live beam
## crosses around the bird's arrival (WALL_FROM..WALL_TO). No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var at := sim.steps_to_wall(side)
	var reach := HALF_H + SimConfig.BIRD_RADIUS + MARGIN
	var blocked := 0
	for i in rows.size():
		var live := false
		for d in range(WALL_FROM, WALL_TO + 1, WALL_STEP):
			if live_in(i, at + d):
				live = true
		if not live:
			continue
		for slot in SimConfig.SLOT_COUNT:
			if absi(SimConfig.slot_center_y(slot) - rows[i]) < reach:
				blocked |= 1 << slot
	var safe := ((1 << SimConfig.SLOT_COUNT) - 1) & ~blocked
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
	# Generated Beam Gates: the free run is also one a bird can get to through
	# the beams from anywhere in the other wall's free run, the wall it bounces
	# off first.
	if calm_spikes > 0:
		var both := safe & reachable_slots(sim, side)
		var all := (1 << SimConfig.SLOT_COUNT) - 1
		var both_need := mini(sim.room.def.gap, RoomRules.longest_gap(all & ~both))
		if both_need > 0:
			safe = both
			need = both_need
	var out := RoomRules.keep_run(mask, need, safe)
	if calm_spikes > 0 and not exit_ys.is_empty():
		# Bounces until the bird gets to this wall (each scores until the exit
		# opens): does the exit's ghost show by then?
		var heading := 1 if sim.state.vx > 0 else 0
		var hits := 1 if heading == side else 2
		var s := sim.state
		if s.exit_open or s.exit_preview or s.score + hits >= sim.next_exit_score() - 1:
			var e := exit_ys[0]
			while _count(out) > calm_spikes:
				var near := -1
				for slot in SimConfig.SLOT_COUNT:
					if RoomRules.has_slot(out, slot):
						var d := absi(SimConfig.slot_center_y(slot) - e)
						if near < 0 or d < absi(SimConfig.slot_center_y(near) - e):
							near = slot
				out &= ~(1 << near)
	return out


static func _count(mask: int) -> int:
	var n := 0
	for slot in SimConfig.SLOT_COUNT:
		if (mask >> slot) & 1 == 1:
			n += 1
	return n


func kills(sim: GameSim) -> bool:
	for i in rows.size():
		if state(i) == State.ON:
			var y0 := rows[i] - HALF_H
			var y1 := rows[i] + HALF_H
			if sim.bird_touches_rect(beam_left(sim, i), y0, beam_right(sim, i), y1):
				return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(mix_all(h, rows), delays)
	if yields:
		out = mix_all(out, skip)
	return out


## Each row that shows its dashed warning: the beam it turns into.
func warnings(sim: GameSim, out: PackedInt64Array) -> void:
	for i in rows.size():
		if state(i) != State.WARN:
			continue
		add_warning(
			out,
			beam_left(sim, i),
			rows[i] - HALF_H,
			beam_right(sim, i),
			rows[i] + HALF_H,
			warn_ticks - cycle_pos(i),
			ON_TICKS,
			WARN_KILL
		)
