extends Hazard
## A boss (boss rooms: the exit at every SimConfig.BOSS_EVERY points leads into
## one). Every wall bounce is a hit: the room's exit opens after
## SimConfig.BOSS_POINTS of them, in three phases (PHASE_AT points into the
## room). After a phase change the boss waits STAGGER steps before its next
## attack: that wait is the tell for the new phase. When an exit is drawn
## (it opens, with no ghost first in a boss room) the boss breaks
## (`down_at`): it no longer kills and only falls apart, so nothing of it is
## ever in an exit's mouth (ExitZone).
##
## Its attacks run on the phase clock (steps since the phase began, clock()).
## Every player of a seed meets them on the same ticks: speed across is fixed,
## so the bounces, and with them the phase changes, come at the same ticks.
## What a cycle does comes from the boss's own seed (one RNG draw in setup)
## mixed with the cycle number (draw()), so it is known ahead and the wall the
## bird flies to keeps a way to live (adjust_wall, safe_y).
##
## Subclasses: boss_setup, boss_step, boss_down_step, boss_kills, safe_y.

## Room points at which phases 2 and 3 begin.
const PHASE_AT: Array[int] = [7, 14]
## Steps with no new attack after a phase change.
const STAGGER := 70
## Steps from the room's start to phase 1's clock: the reading time out of the
## portal and the simple players' follow-up (ArrivalCheck) see no attack, and
## the first tell (one cycle start) only comes then.
const FIRST_DELAY := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW / 2
## A bird at a height on the wall it reaches must be safe there from WALL_FROM
## to WALL_TO steps around its arrival (sampled every WALL_STEP), else the
## wall gets a free spot where it is (adjust_wall).
const WALL_FROM := -6
const WALL_TO := 30
const WALL_STEP := 6
## Margin added to every safe_y clearance.
const MARGIN := 4 * SimConfig.SUB

## 1 at the first boss portal, 2 at the second, 3 from the third on.
var tier := 1
## 1..3.
var phase := 1
## Room step the phase clock starts at.
var phase_start := FIRST_DELAY
## Room step the boss broke at, or -1.
var down_at := -1
## The boss's own seed (cycle draws).
var seed := 0


func setup(sim: GameSim, rng: SimRng) -> void:
	tier = SimConfig.boss_tier(sim.room.entry_score)
	seed = rng.next_u32()
	boss_setup(sim)


func step(sim: GameSim) -> void:
	if down_at < 0 and (sim.state.exit_open or sim.state.exit_preview):
		down_at = t
	if down_at >= 0:
		boss_down_step(sim)
		return
	var p := phase_of(sim.room.points)
	if p != phase:
		phase = p
		phase_start = t + STAGGER
		on_phase()
	boss_step(sim)


func kills(sim: GameSim) -> bool:
	if down_at >= 0:
		return false
	return boss_kills(sim)


## The phase at `points` bounces into the room.
static func phase_of(points: int) -> int:
	if points >= PHASE_AT[1]:
		return 3
	if points >= PHASE_AT[0]:
		return 2
	return 1


## Steps into the phase (negative while the boss waits).
func clock() -> int:
	return t - phase_start


## Phase clock `steps` from now.
func clock_in(steps: int) -> int:
	return t + steps - phase_start


## A number drawn for cycle `k` (salt picks which), 0..2^32-1.
func draw(k: int, salt: int) -> int:
	return SimHash.mix(SimHash.mix(SimHash.mix(SimHash.SEED, seed), k), salt)


## Where the bird is `steps` from now if it flies straight on, bouncing off the
## walls (x only).
static func x_after(sim: GameSim, steps: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var lo := sim.room.wall_left() + r
	var hi := sim.room.wall_right() - r
	var span := hi - lo
	if span <= 0:
		return sim.state.x
	var pos := sim.state.x - lo if sim.state.vx > 0 else 2 * span - (sim.state.x - lo)
	pos = posmod(pos + steps * absi(sim.state.vx), 2 * span)
	return lo + (pos if pos <= span else 2 * span - pos)


## Keeps a way to live on the wall the bird flies to: a run of free slots
## whose centres are all safe around the bird's arrival (safe_y), as wide as
## the room's gap, or as the widest band the boss leaves safe when that is
## narrower. A wall without one gets the safe run of that width nearest its
## free run cleared, so the way through is never a single hole in the boss's
## reach. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	if down_at >= 0:
		return mask
	var at := sim.steps_to_wall(side)
	var blocked := 0
	for slot in SimConfig.SLOT_COUNT:
		if not _safe_span(SimConfig.slot_center_y(slot), at):
			blocked |= 1 << slot
	var safe := ((1 << SimConfig.SLOT_COUNT) - 1) & ~blocked
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
	return RoomRules.keep_run(mask, need, safe)


func _safe_span(y: int, at: int) -> bool:
	for d in range(WALL_FROM, WALL_TO + 1, WALL_STEP):
		if not safe_y(y, at + d):
			return false
	return true


## True if a bird at height `y` by a wall is clear of the boss `steps` from
## now (as far as its schedule tells; aimed attacks don't count).
func safe_y(_y: int, _steps: int) -> bool:
	return true


func boss_setup(_sim: GameSim) -> void:
	pass


## The phase just changed (phase is the new one).
func on_phase() -> void:
	pass


func boss_step(_sim: GameSim) -> void:
	pass


## A step after the boss broke (no attacks, no kills).
func boss_down_step(_sim: GameSim) -> void:
	pass


func boss_kills(_sim: GameSim) -> bool:
	return false


func checksum(h: int) -> int:
	return mix_all(h, [tier, phase, phase_start, down_at, seed])
