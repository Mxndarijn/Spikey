extends Hazard
## One shutter column (Shutter Gates): a full-height bar with a gap that slides
## up and down. Both parts of the bar kill; the gap is the way through.

const HALF_W := 8 * SimConfig.SUB
## The gap is always this tall (the bird is 28 px).
const GAP := 176 * SimConfig.SUB
## The gap's centre ping-pongs between these heights (the gap's edges stay
## 40 px clear of the ceiling and floor lines).
const GAP_MIN_Y := 162 * SimConfig.SUB
const GAP_MAX_Y := 478 * SimConfig.SUB
## The bar runs from the ceiling line to the floor line.
const TOP := SimConfig.KILL_TOP
const BOTTOM := SimConfig.KILL_BOTTOM

## The second gate follows the first this many steps behind, so the two gaps
## stay close (about 35 px apart at most) and form one moving tunnel.
const LAG := 40
## No spike on the wall ahead within this of where the gap next to it will be.
const WALL_CLEAR := 80 * SimConfig.SUB
## An exit is only planned within this of where the gap of the last gate before
## its wall will be when the bird comes through it (about 27 steps from the
## wall: one hop up, or a short drop).
const EXIT_REACH := 80 * SimConfig.SUB
## A revived bird (the exit stayed where it was): the gap of the first gate it
## meets is at most this far from the bird's height, toward the exit.
const REVIVE_REACH := 80 * SimConfig.SUB

## Column centre x.
var x := 0
## Follows the gate before it in the room (same period, LAG behind).
var follows := false
## The leader's partner gate (found at setup), or null.
var partner: Hazard = null
## Steps per up-and-down cycle.
var period := 400
## Offset into the cycle, drawn at setup.
var phase := 0
## Gap centre right now.
var gap_y := 0


func _init(p_x: int = 0, p_period: int = 400, p_follows: bool = false) -> void:
	kind = "gate"
	x = p_x
	period = p_period
	follows = p_follows


## The gap starts at the bird's height (it just came in at a wall and can't
## slow down), moving up or down at random. If an exit is already open or
## planned (a revive), the gaps lead from the bird to it instead.
func setup(sim: GameSim, rng: SimRng) -> void:
	partner = null
	# Hazards are set up in order, so the follower finds the leader (already
	# set up) and links both ways.
	for h in sim.room.hazards:
		if follows and h != self and h.kind == kind:
			partner = h
			h.partner = self
	if follows and partner != null:
		period = partner.period
		# The leader now knows both gates, so it can aim the last one.
		if sim.state.exit_open or sim.state.exit_preview:
			partner.aim_at_exit(sim)
		phase = posmod(partner.phase - LAG, period)
		_place()
		return
	var down := rng.next_below(2) == 0
	phase = _phase_for(sim.entry_y(), 0, down)
	if sim.state.exit_open or sim.state.exit_preview:
		aim_at_exit(sim)
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	gap_y = gap_at(t)


## Gap centre at room step `tick`.
func gap_at(tick: int) -> int:
	return GAP_MIN_Y + SimTrig.ping_pong(tick + phase, period, GAP_MAX_Y - GAP_MIN_Y)


## The phase that puts this gate's gap centre at `y` (kept inside its range) at
## room step `tick`, moving down the screen then (`down`) or up.
func _phase_for(y: int, tick: int, down: bool) -> int:
	var span := GAP_MAX_Y - GAP_MIN_Y
	var at := clampi(y - GAP_MIN_Y, 0, span)
	var half := period / 2
	var rising_phase := at * half / span
	return posmod((rising_phase if down else period - rising_phase) - tick, period)


## The gate (this one or its partner) the bird passes last before wall `side`.
func _last_before(side: int) -> Hazard:
	if partner != null and (partner.x > x) == (side == 1):
		return partner
	return self


## Room steps from now until the bird, flying straight on, is level with `gate`
## on its way into wall `side`.
func _steps_to_pass(sim: GameSim, gate: Hazard, side: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var wall_x := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	return maxi(sim.steps_to_wall(side) - absi(wall_x - gate.x) / SimConfig.SPEED_X, 0)


## Leader only, at setup with an exit already open or planned (the bird was
## revived; the exit stayed where it was): sets the cycle so the gaps move from
## the bird toward the exit. The first gate the bird meets has its gap within
## REVIVE_REACH of the bird, and the last gate before the exit's wall has its
## gap at the exit's height when the bird comes through on its way there, or
## as near as the gap gets by then. No RNG.
func aim_at_exit(sim: GameSim) -> void:
	var s := sim.state
	var last := _last_before(s.exit_side)
	var first := _last_before(0 if s.vx > 0 else 1)
	# Where in the leader's cycle each of the two moments is (the follower runs
	# LAG steps behind it).
	var first_at := absi(first.x - s.x) / SimConfig.SPEED_X - (0 if first == self else LAG)
	var last_at := _steps_to_pass(sim, last, s.exit_side) - (0 if last == self else LAG)
	# How far the gap slides between the two.
	var slide := (GAP_MAX_Y - GAP_MIN_Y) * (last_at - first_at) / (period / 2)
	var reach := maxi(REVIVE_REACH + slide, 0)
	var from := sim.entry_y()
	var target := clampi(clampi(s.exit_a_y, GAP_MIN_Y, GAP_MAX_Y), from - reach, from + reach)
	phase = _phase_for(target, t + last_at, target > from)
	_place()


## The leader keeps the wall ahead open where the gate next to it will have
## its gap when the bird gets there.
func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if follows:
		return
	var s := sim.state
	var near := _last_before(1 if s.vx > 0 else 0)
	var steps := absi(near.x - s.x) / SimConfig.SPEED_X
	var gap: int = near.gap_at(t + steps)
	var mask := s.right_spikes if s.vx > 0 else s.left_spikes
	for slot in SimConfig.SLOT_COUNT:
		if absi(SimConfig.slot_center_y(slot) - gap) < WALL_CLEAR:
			mask &= ~(1 << slot)
	if s.vx > 0:
		s.right_spikes = mask
	else:
		s.left_spikes = mask


## An exit goes only where the bird can get to from the gap of the last gate
## before its wall: within EXIT_REACH of where that gap will be when the bird
## comes through it on its way to the exit.
func blocks_exit(sim: GameSim, side: int, y: int) -> bool:
	# The leader answers for the pair.
	if follows and partner != null:
		return false
	var last := _last_before(side)
	var gap: int = last.gap_at(t + _steps_to_pass(sim, last, side))
	return absi(y - gap) > EXIT_REACH


func gap_top() -> int:
	return gap_y - GAP / 2


func gap_bottom() -> int:
	return gap_y + GAP / 2


func kills(sim: GameSim) -> bool:
	if sim.bird_touches_rect(x - HALF_W, TOP, x + HALF_W, gap_top()):
		return true
	return sim.bird_touches_rect(x - HALF_W, gap_bottom(), x + HALF_W, BOTTOM)


func checksum(h: int) -> int:
	return mix_all(h, [x, period, phase, gap_y, int(follows)])
