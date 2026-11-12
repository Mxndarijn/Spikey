extends "res://sim/hazards/boss.gd"
## The Crusher (boss): a spiked press as wide as the cage, which at rest is the
## ceiling, and in phases 2 and 3 a spiked floor plate that rises under it.
## Phase 1: the press shakes (TELL steps, the line its teeth will stop at is
## shown), slams down to a height and holds, then lifts. Phase 2, the jaw: press
## and plate leave a lane; every cycle the next lane is shown, then both move
## to it. A lane overlaps the last one by at least the bird plus a hop. Phase
## 3: the jaw, and a crate drops through the lane in a marked column, never
## one the bird will be crossing while it falls (x_after).
## Tier 2: the press slams lower, the lane is narrower and two crates drop;
## tier 3 narrower still.

enum Crate { NONE, MARK, FALL }

const CYCLE := 240
const TELL := SimConfig.WARN_TICKS
## Press: its bottom edge (`press_y`) at rest; its teeth reach TEETH below it.
## At rest the teeth are the ceiling's.
const TEETH := 24 * SimConfig.SUB
## The deadly part of the teeth (a little short of their tips).
const BITE := 20 * SimConfig.SUB
const PRESS_REST := SimConfig.KILL_TOP - TEETH
const PLATE_REST := SimConfig.KILL_BOTTOM + TEETH
const SLAM_DOWN := 12 * SimConfig.SUB
const LIFT := 6 * SimConfig.SUB
## Phase 1: when in the cycle the press goes down and lifts.
const SLAM_AT := TELL
const LIFT_AT := 170
## Where its teeth stop (two heights a cycle picks from; tier 2 and up: lower).
const SLAMS: Array[int] = [250 * SimConfig.SUB, 320 * SimConfig.SUB]
const SLAM_TIER := 30 * SimConfig.SUB
## Jaw: half the lane between the teeth, by tier.
const LANE_HALF: Array[int] = [116 * SimConfig.SUB, 100 * SimConfig.SUB, 90 * SimConfig.SUB]
const LANE_FIRST := 340 * SimConfig.SUB
const LANE_STEP_MIN := 40 * SimConfig.SUB
## The most a lane moves (tier 1, then tiers 2 and 3).
const LANE_STEP_MAX: Array[int] = [100 * SimConfig.SUB, 80 * SimConfig.SUB, 80 * SimConfig.SUB]
const JAW_SPEED := 3 * SimConfig.SUB
## Crates (phase 3).
const CRATE_AT := 110
const CRATE_FALL := TELL + CRATE_AT
const CRATE_HALF := 16 * SimConfig.SUB
const CRATE_SPEED := 6 * SimConfig.SUB
const COLUMNS := 7
const COLUMN_X0 := 60 * SimConfig.SUB
const COLUMN_STEP := 40 * SimConfig.SUB
## A crate's column keeps this far (centre to centre) from the bird while it falls.
const CRATE_CLEAR := 60 * SimConfig.SUB

## The press's bottom edge and the plate's top edge (their teeth point at the
## lane between them).
var press_y := PRESS_REST
var plate_y := PLATE_REST
## Phase 1: where this cycle's slam stops (the press's bottom edge).
var slam_y := 0
## Jaw: the lane's centre this cycle comes from and goes to.
var lane_from := LANE_FIRST
var lane_to := LANE_FIRST
## True while the next press (and plate) line is shown.
var telling := false
var crate_x: Array[int] = [0, 0]
var crate_y: Array[int] = [0, 0]
var crate: Array[int] = [Crate.NONE, Crate.NONE]
## True once the jaw has a lane (phase 2 on).
var jaw := false
## This phase's cycle the lane was drawn for.
var _k := -1


func _init() -> void:
	kind = "boss_crusher"


func lane_half() -> int:
	return LANE_HALF[tier - 1]


func slam_of(k: int) -> int:
	return SLAMS[draw(k, 1) % SLAMS.size()] + (SLAM_TIER if tier >= 2 else 0) - TEETH


func boss_step(sim: GameSim) -> void:
	telling = false
	var c := clock()
	var press_to := press_y if jaw else PRESS_REST
	var plate_to := plate_y
	if c >= 0 and phase == 1:
		var k := c / CYCLE
		var lt := c % CYCLE
		slam_y = slam_of(k)
		telling = lt < SLAM_AT
		press_to = slam_y if lt >= SLAM_AT and lt < LIFT_AT else PRESS_REST
	elif c >= 0:
		var k := c / CYCLE
		var lt := c % CYCLE
		if _k != k:
			_k = k
			lane_from = lane_to if jaw else -1
			lane_to = _next_lane(k) if jaw else LANE_FIRST
			jaw = true
		telling = lt < TELL
		var lane := lane_to if lt >= TELL else lane_from
		if lane >= 0:
			press_to = lane - lane_half() - TEETH
			plate_to = lane + lane_half() + TEETH
		if phase == 3:
			_crates(sim, lt)
	press_y = _toward(press_y, press_to, SLAM_DOWN if phase == 1 else JAW_SPEED, LIFT)
	plate_y = _toward(plate_y, plate_to, JAW_SPEED, JAW_SPEED)


func on_phase() -> void:
	_k = -1
	crate = [Crate.NONE, Crate.NONE]


## The centre of cycle `k`'s lane: a step up or down from the last one.
func _next_lane(k: int) -> int:
	var lo := PRESS_REST + TEETH + lane_half()
	var hi := PLATE_REST - TEETH - lane_half()
	var span := LANE_STEP_MAX[tier - 1] - LANE_STEP_MIN
	var key := k + phase * 1000
	var d := LANE_STEP_MIN + draw(key, 2) % (span / SimConfig.SUB + 1) * SimConfig.SUB
	if draw(key, 3) % 2 == 0:
		d = -d
	var to := lane_from + d
	if to < lo or to > hi:
		to = lane_from - d
	return clampi(to, lo, hi)


## Moves `from` toward `to`, at most `down` a step downward and `up` upward.
static func _toward(from: int, to: int, down: int, up: int) -> int:
	if to > from:
		return mini(from + down, to)
	return maxi(from - up, to)


func _crates(sim: GameSim, lt: int) -> void:
	if lt == CRATE_AT:
		var count := 2 if tier >= 2 else 1
		var used := -1
		for i in count:
			var col := _pick_column(sim, used, i)
			used = col
			crate[i] = Crate.MARK
			crate_x[i] = COLUMN_X0 + col * COLUMN_STEP
		for i in range(count, 2):
			crate[i] = Crate.NONE
	for i in 2:
		if crate[i] == Crate.NONE:
			continue
		if crate[i] == Crate.MARK:
			crate_y[i] = press_y + TEETH + CRATE_HALF
			if lt >= CRATE_FALL:
				crate[i] = Crate.FALL
		else:
			crate_y[i] += CRATE_SPEED
			if crate_y[i] + CRATE_HALF >= plate_y - TEETH:
				crate[i] = Crate.NONE


## A column no crate falling from CRATE_FALL meets the bird in (it keeps
## CRATE_CLEAR from x_after the whole fall), drawn among those; the one
## furthest from it if none is. Not `used`.
func _pick_column(sim: GameSim, used: int, i: int) -> int:
	var fall := (2 * lane_half()) / CRATE_SPEED + 2
	var ok: Array[int] = []
	var far := 0
	var far_d := -1
	for col in COLUMNS:
		if col == used:
			continue
		var x := COLUMN_X0 + col * COLUMN_STEP
		var near := SimConfig.WORLD_W
		for s in range(CRATE_FALL - CRATE_AT, CRATE_FALL - CRATE_AT + fall + 1, 2):
			near = mini(near, absi(x_after(sim, s) - x))
		if near >= CRATE_CLEAR:
			ok.append(col)
		if near > far_d:
			far_d = near
			far = col
	if ok.is_empty():
		return far
	return ok[draw(_k + phase * 1000, 10 + i) % ok.size()]


func boss_down_step(_sim: GameSim) -> void:
	telling = false
	crate = [Crate.NONE, Crate.NONE]
	press_y = _toward(press_y, PRESS_REST, LIFT, LIFT)
	plate_y = _toward(plate_y, PLATE_REST, LIFT, LIFT)


func boss_kills(sim: GameSim) -> bool:
	if sim.state.y - SimConfig.BIRD_RADIUS <= press_y + BITE:
		return true
	if sim.state.y + SimConfig.BIRD_RADIUS >= plate_y - BITE:
		return true
	for i in 2:
		if crate[i] == Crate.FALL:
			var x := crate_x[i]
			var y := crate_y[i]
			if sim.bird_touches_rect(
				x - CRATE_HALF, y - CRATE_HALF, x + CRATE_HALF, y + CRATE_HALF
			):
				return true
	return false


## The press and plate a schedule can bring by `steps` from now: the lowest
## press and highest plate of now and the schedule then, a lane not yet drawn
## (the next cycle's) moving as far as it can.
func safe_y(y: int, steps: int) -> bool:
	var top := press_y
	var bottom := plate_y
	var c := clock_in(steps)
	if c >= 0 and phase == 1:
		var lt := c % CYCLE
		if lt >= SLAM_AT and lt < LIFT_AT:
			top = maxi(top, slam_of(c / CYCLE))
	elif c >= 0:
		var k := c / CYCLE
		var lt := c % CYCLE
		var lane := lane_to if jaw else LANE_FIRST
		var spread := 0
		if k > _k and jaw and lt >= TELL:
			spread = mini((lt - TELL) * JAW_SPEED, LANE_STEP_MAX[tier - 1])
		top = maxi(top, lane - lane_half() - TEETH + spread)
		bottom = mini(bottom, lane + lane_half() + TEETH - spread)
	var r := SimConfig.BIRD_RADIUS + MARGIN
	return y - r > top + BITE and y + r < bottom - BITE


func checksum(h: int) -> int:
	return mix_all(
		super(h),
		[
			press_y,
			plate_y,
			slam_y,
			lane_from,
			lane_to,
			int(telling),
			int(jaw),
			crate_x[0],
			crate_y[0],
			crate[0],
			crate_x[1],
			crate_y[1],
			crate[1],
			_k
		]
	)
