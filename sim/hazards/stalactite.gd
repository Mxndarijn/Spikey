extends Hazard
## Stalactite Run: a rock column with a stalactite hanging from the top and a
## stalagmite standing from the bottom, leaving a gap. After every wall bounce
## the gap slides to a new height. The rock kills.

## Gap between the two rocks (tip to tip).
const GAP := 150 * SimConfig.SUB
## Width of the rock column.
const HALF_W := 22 * SimConfig.SUB
## Range of the gap's centre.
const GAP_MIN := 150 * SimConfig.SUB
const GAP_MAX := 490 * SimConfig.SUB
## After a bounce, the column the bird meets first gets its gap within REACH
## of the bird's height (it has about half a second to get there), and the
## other column within MAX_STEP of that, so there is always a way through.
## Out of a portal (a bounce at room step 0) the first gap stays at the bird's
## height instead, since the player hasn't seen the room yet.
const REACH := 40 * SimConfig.SUB
const MAX_STEP := 60 * SimConfig.SUB
## No wall spike within this of the gap next to the wall ahead.
const WALL_CLEAR := 70 * SimConfig.SUB
## How fast the gap slides to its new height, per step.
const SLIDE := 3 * SimConfig.SUB

## Column centre, sub-units.
var x := 0
## Gap centre now, and where it is sliding to.
var gap_y := 0
var target_y := 0
## Follows the stalactite before it in the room: the leader picks both gaps.
var follows := false
## The leader's partner column (found at setup), or null.
var partner: Hazard = null


func _init(p_x: int = 0, p_follows: bool = false) -> void:
	kind = "stalactite"
	x = p_x
	follows = p_follows


func setup(sim: GameSim, _rng: SimRng) -> void:
	partner = null
	# Hazards are set up in order, so the follower finds the leader (already
	# set up) and links both ways.
	if follows:
		for h in sim.room.hazards:
			if h != self and h.kind == kind:
				partner = h
				h.partner = self
	# Start with the gap at the bird's height: it enters at a wall and reaches
	# the first column before it could climb or drop far.
	gap_y = clampi(sim.entry_y(), GAP_MIN, GAP_MAX)
	target_y = gap_y


## The leader picks new gaps for both columns (see REACH); a follower waits
## for it.
func on_bounce(sim: GameSim, rng: SimRng) -> void:
	if follows:
		return
	var near: Hazard = self
	var far: Hazard = partner
	# The bird just turned: it meets the column nearest the wall it left first.
	if partner != null and (partner.x > x) == (sim.state.vx < 0):
		near = partner
		far = self
	if t == 0:
		# Just came out of a portal into this room: the player hasn't seen it
		# yet, so the gap ahead stays at the bird's height (set in setup).
		near.target_y = near.gap_y
	else:
		near.target_y = _around(rng, sim.state.y, REACH)
	if far != null:
		far.target_y = _around(rng, near.target_y, MAX_STEP)
	_clear_wall_ahead(sim, far if far != null else near)


## The wall the bird is heading to keeps its spikes away from the gap of the
## column next to it, so the way out of that gap is open.
static func _clear_wall_ahead(sim: GameSim, column: Hazard) -> void:
	var s := sim.state
	var mask := s.right_spikes if s.vx > 0 else s.left_spikes
	for slot in SimConfig.SLOT_COUNT:
		if absi(SimConfig.slot_center_y(slot) - column.target_y) < WALL_CLEAR:
			mask &= ~(1 << slot)
	if s.vx > 0:
		s.right_spikes = mask
	else:
		s.left_spikes = mask


static func _around(rng: SimRng, center: int, spread: int) -> int:
	var lo := maxi(GAP_MIN, center - spread)
	var hi := mini(GAP_MAX, center + spread)
	if lo > hi:
		return clampi(center, GAP_MIN, GAP_MAX)
	return lo + rng.next_below(hi - lo + 1)


func step(_sim: GameSim) -> void:
	if gap_y < target_y:
		gap_y = mini(gap_y + SLIDE, target_y)
	elif gap_y > target_y:
		gap_y = maxi(gap_y - SLIDE, target_y)


## Tip of the hanging rock and of the standing rock.
func top_tip() -> int:
	return gap_y - GAP / 2


func bottom_tip() -> int:
	return gap_y + GAP / 2


func kills(sim: GameSim) -> bool:
	return (
		sim.bird_touches_rect(x - HALF_W, 0, x + HALF_W, top_tip())
		or sim.bird_touches_rect(x - HALF_W, bottom_tip(), x + HALF_W, SimConfig.WORLD_H)
	)


func checksum(h: int) -> int:
	return mix_all(h, [x, gap_y, target_y, int(follows)])
