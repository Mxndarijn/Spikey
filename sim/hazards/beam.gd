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
