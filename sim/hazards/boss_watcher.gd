extends "res://sim/hazards/boss.gd"
## The Watcher (boss): an eye in the ceiling with beam emitters down both walls.
## Phase 1: some of the ROWS fire across the cage (BEAM_ON steps) after a
## dashed warning (BEAM_TELL steps). Phase 2, the gaze: the bird's height is marked,
## the spike on the wall ahead glows, and GAZE_TELL steps later a dart flies across
## that lane. Phase 3: fewer rows, then a gaze dart, each cycle.
## Tier 2 lights one more row; tier 3 gazes faster. A cycle never lights more
## than MAX_RUN rows in a row, so a dark row is always within reach.

enum Beam { OFF, WARN, ON }
enum Dart { NONE, MARK, FLY }

const ROWS: Array[int] = [
	200 * SimConfig.SUB,
	260 * SimConfig.SUB,
	320 * SimConfig.SUB,
	380 * SimConfig.SUB,
	440 * SimConfig.SUB,
	500 * SimConfig.SUB,
	560 * SimConfig.SUB,
]
const CYCLE := 240
## Beams warn as long as every tell (SimConfig.WARN_TICKS).
const BEAM_TELL := SimConfig.WARN_TICKS
## The gaze dart is not a beam: its mark is a 1 s reaction plus the hop out of
## its lane, since it flies from the wall the bird is heading to (phase 3 marks
## at GAZE_AT and must fly before the cycle ends).
const GAZE_TELL := 75
const BEAM_ON := 70
## Half the thickness of a live beam's deadly core.
const HALF_H := 6 * SimConfig.SUB
const MAX_RUN := 3
## Phase 2: a gaze every GAZE steps (GAZE_FAST from tier 3); a dart is across
## (40 steps) before the next mark.
const GAZE := 120
const GAZE_FAST := 115
## Phase 3: when in its cycle the gaze marks.
const GAZE_AT := 130
const DART_SPEED := 10 * SimConfig.SUB
const DART_LEN := 34 * SimConfig.SUB
const DART_HALF := 10 * SimConfig.SUB
## Marked lanes stay this far from the ceiling and floor lines.
const LANE_MIN := 110 * SimConfig.SUB
const LANE_MAX := 530 * SimConfig.SUB

## Rows of this cycle (bit i = ROWS[i]) and what they do now.
var lit := 0
var beam := Beam.OFF
## Steps into the beams' cycle (for the painter's warning).
var beam_t := 0
## The gaze dart: its lane, the wall it comes from (0 left, 1 right), its tip.
var dart := Dart.NONE
var dart_lane := 0
var dart_side := 0
var dart_x := 0
## Steps into the gaze (for the painter).
var dart_t := 0
var _lit_k := -1


func _init() -> void:
	kind = "boss_watcher"


## The rows cycle `k` of phase `p` lights.
func lit_rows(p: int, k: int) -> int:
	var count := (3 if p == 1 else 2) + (1 if tier >= 2 else 0)
	var rng := SimRng.new(draw(k, p))
	for _try in 20:
		var mask := 0
		var n := 0
		while n < count:
			var r := rng.next_below(ROWS.size())
			if (mask >> r) & 1 == 0:
				mask |= 1 << r
				n += 1
		if _longest_run(mask) <= MAX_RUN:
			return mask
	return 0b1010101 & ((1 << ROWS.size()) - 1)


static func _longest_run(mask: int) -> int:
	var best := 0
	var run := 0
	for i in ROWS.size():
		run = run + 1 if (mask >> i) & 1 == 1 else 0
		best = maxi(best, run)
	return best


func gaze_every() -> int:
	return GAZE_FAST if tier >= 3 else GAZE


func boss_step(sim: GameSim) -> void:
	beam = Beam.OFF
	var c := clock()
	if c < 0:
		dart = Dart.NONE
		return
	if phase != 2:
		var k := c / CYCLE
		beam_t = c % CYCLE
		if _lit_k != k:
			_lit_k = k
			lit = lit_rows(phase, k)
		if beam_t < BEAM_TELL:
			beam = Beam.WARN
		elif beam_t < BEAM_TELL + BEAM_ON:
			beam = Beam.ON
	var g := c % gaze_every() if phase == 2 else (c % CYCLE) - GAZE_AT
	if phase != 1:
		_gaze(sim, g)


func _gaze(sim: GameSim, g: int) -> void:
	if g == 0:
		dart = Dart.MARK
		dart_lane = clampi(sim.state.y, LANE_MIN, LANE_MAX)
		dart_side = 1 if sim.state.vx > 0 else 0
	if dart == Dart.MARK:
		dart_t = g
		if g >= GAZE_TELL:
			dart = Dart.FLY
			dart_x = sim.room.wall_right() if dart_side == 1 else sim.room.wall_left()
	elif dart == Dart.FLY:
		dart_x += -DART_SPEED if dart_side == 1 else DART_SPEED
		if dart_x < -DART_LEN or dart_x > SimConfig.WORLD_W + DART_LEN:
			dart = Dart.NONE


func boss_down_step(_sim: GameSim) -> void:
	beam = Beam.OFF
	dart = Dart.NONE


func boss_kills(sim: GameSim) -> bool:
	if beam == Beam.ON:
		for i in ROWS.size():
			if (lit >> i) & 1 == 1:
				var y := ROWS[i]
				if sim.bird_touches_rect(
					sim.room.wall_left(), y - HALF_H, sim.room.wall_right(), y + HALF_H
				):
					return true
	if dart == Dart.FLY:
		var back := dart_x + DART_LEN if dart_side == 1 else dart_x - DART_LEN
		if sim.bird_touches_rect(dart_x, dart_lane - DART_HALF, back, dart_lane + DART_HALF):
			return true
	return false


func safe_y(y: int, steps: int) -> bool:
	if phase == 2:
		return true
	var c := clock_in(steps)
	if c < 0:
		return true
	var lt := c % CYCLE
	if lt < BEAM_TELL or lt >= BEAM_TELL + BEAM_ON:
		return true
	var mask := lit_rows(phase, c / CYCLE)
	for i in ROWS.size():
		if (mask >> i) & 1 == 1 and absi(y - ROWS[i]) < HALF_H + SimConfig.BIRD_RADIUS + MARGIN:
			return false
	return true


func checksum(h: int) -> int:
	return mix_all(
		super(h), [lit, beam, beam_t, dart, dart_lane, dart_side, dart_x, dart_t, _lit_k]
	)


## The rows that show their dashed warning, and the lane the gaze has marked.
func warnings(sim: GameSim, out: PackedInt64Array) -> void:
	if down_at >= 0 or clock() < 0:
		return
	if beam == Beam.WARN:
		for i in ROWS.size():
			if (lit >> i) & 1 == 1:
				add_warning(
					out,
					sim.room.wall_left(),
					ROWS[i] - HALF_H,
					sim.room.wall_right(),
					ROWS[i] + HALF_H,
					BEAM_TELL - beam_t,
					BEAM_ON,
					WARN_KILL
				)
	if dart == Dart.MARK:
		var dur := (SimConfig.WORLD_W + DART_LEN) / DART_SPEED + 1
		add_warning(
			out,
			0,
			dart_lane - DART_HALF,
			SimConfig.WORLD_W,
			dart_lane + DART_HALF,
			GAZE_TELL - dart_t,
			dur,
			WARN_KILL
		)
