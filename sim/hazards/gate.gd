extends Hazard
## One shutter column (Shutter Gates): a full-height bar with a gap that slides
## up and down. Both parts of the bar kill; the gap is the way through.

const HALF_W := 8 * SimConfig.SUB
## The gap is always this tall (the bird is 28 px).
const GAP := 150 * SimConfig.SUB
## The gap's centre ping-pongs between these heights.
const GAP_MIN_Y := 150 * SimConfig.SUB
const GAP_MAX_Y := 490 * SimConfig.SUB
## The bar runs from the ceiling line to the floor line.
const TOP := SimConfig.KILL_TOP
const BOTTOM := SimConfig.KILL_BOTTOM

## The second gate follows the first this many steps behind, so the two gaps
## stay close (about 35 px apart at most) and form one moving tunnel.
const LAG := 40
## No spike on the wall ahead within this of where the gap next to it will be.
const WALL_CLEAR := 70 * SimConfig.SUB

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
## slow down), moving up or down at random.
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
		phase = posmod(partner.phase - LAG, period)
		_place()
		return
	var span := GAP_MAX_Y - GAP_MIN_Y
	var at := clampi(sim.entry_y() - GAP_MIN_Y, 0, span)
	var half := period / 2
	var rising_phase := at * half / span
	phase = rising_phase if rng.next_below(2) == 0 else period - rising_phase
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	gap_y = gap_at(t)


## Gap centre at room step `tick`.
func gap_at(tick: int) -> int:
	return GAP_MIN_Y + SimTrig.ping_pong(tick + phase, period, GAP_MAX_Y - GAP_MIN_Y)


## The leader keeps the wall ahead open where the gate next to it will have
## its gap when the bird gets there.
func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if follows:
		return
	var s := sim.state
	var near: Hazard = self
	if partner != null and (partner.x > x) == (s.vx > 0):
		near = partner
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
