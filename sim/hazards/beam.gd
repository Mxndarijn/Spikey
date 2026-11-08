extends Hazard
## Beam Gates: ROWS (or fewer) pairs of wall emitters, each firing a full-width beam on its
## own beat. A dashed warning flickers before a beam turns on; live beams kill.
## Beams take turns (one starts every PERIOD / row count steps and each stays on for
## a little more than that), so at most two are on at once and the other rows
## are always open.

enum State { OFF, WARN, ON }

## Rows in the Beam Gates room.
const ROWS := 4
const PERIOD := 180
const WARN_TICKS := 40
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

## Centre height of each row's beam.
var rows: Array[int] = []
## Steps before each row's first warning (its offset into the beat).
var delays: Array[int] = []


## `count` rows; fewer rows sit further apart (Double Trouble uses 3, so a
## second hazard always has room to dodge between them).
func _init(count: int = ROWS) -> void:
	kind = "beam"
	rows.resize(count)
	delays.resize(count)


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
	if p < 0 or p >= WARN_TICKS + ON_TICKS:
		return State.OFF
	return State.WARN if p < WARN_TICKS else State.ON


## 0..1024 how far into the warning (0 outside it).
func warn_progress(i: int) -> int:
	if state(i) != State.WARN:
		return 0
	return SimTrig.ONE * cycle_pos(i) / WARN_TICKS


func live_count() -> int:
	var n := 0
	for i in rows.size():
		if state(i) == State.ON:
			n += 1
	return n


func kills(sim: GameSim) -> bool:
	var left := sim.room.wall_left()
	var right := sim.room.wall_right()
	for i in rows.size():
		if state(i) == State.ON:
			if sim.bird_touches_rect(left, rows[i] - HALF_H, right, rows[i] + HALF_H):
				return true
	return false


func checksum(h: int) -> int:
	return mix_all(mix_all(h, rows), delays)
