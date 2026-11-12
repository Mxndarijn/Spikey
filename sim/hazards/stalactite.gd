extends Hazard
## Stalactite Run: a rock column with a stalactite hanging from the top and a
## stalagmite standing from the bottom, leaving a gap. After every wall bounce
## the gap slides to a new height. The rock kills.
##
## Variants: a column can lose its top or bottom rock (top, bottom), have a
## smaller or bigger gap (gap) or be thinner (half_w). A fixed column
## (fixed_lo >= 0) keeps its gap round the bird's hop where it came in (clamped
## to fixed_lo..fixed_hi) for the whole room.

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
## A fixed gap sits this far above where the bird came in: a bird holding its
## height hops up to about 60 px over it, so this is the middle of its hop.
const HOP_MID := 30 * SimConfig.SUB
## A fixed column this close to a wall keeps that wall's exit inside its gap.
const EXIT_NEAR := 120 * SimConfig.SUB

## Column centre, sub-units.
var x := 0
## Gap centre now, and where it is sliding to.
var gap_y := 0
var target_y := 0
## Follows the stalactite before it in the room: the leader picks both gaps.
var follows := false
## The leader's partner column (found at setup), or null.
var partner: Hazard = null
## Which rocks the column has: hanging from the top, standing from the bottom.
var top := true
var bottom := true
## Gap between the tips, and half the column's width.
var gap := GAP
var half_w := HALF_W
## A fixed gap: its centre range (sub-units), or -1 for a gap that moves.
var fixed_lo := -1
var fixed_hi := -1


func _init(p_x: int = 0, p_follows: bool = false) -> void:
	kind = "stalactite"
	x = p_x
	follows = p_follows


func setup(sim: GameSim, _rng: SimRng) -> void:
	partner = null
	if fixed_lo >= 0:
		gap_y = clampi(FairLanes.entry_y(sim) - HOP_MID, fixed_lo, fixed_hi)
		target_y = gap_y
		return
	# Hazards are set up in order, so the follower finds the leader (already
	# set up) and links both ways.
	if follows:
		for h in sim.room.hazards:
			if h != self and h.kind == kind:
				partner = h
				h.partner = self
	# Start with the gap at the bird's height: it enters at a wall and reaches
	# the first column before it could climb or drop far.
	gap_y = clampi(FairLanes.entry_y(sim), GAP_MIN, GAP_MAX)
	target_y = gap_y


## The leader picks new gaps for both columns (see REACH); a follower waits
## for it.
func on_bounce(sim: GameSim, rng: SimRng) -> void:
	if follows:
		return
	if fixed_lo >= 0:
		# Fixed columns share one gap: keep the way out of it open.
		_clear_wall_ahead(sim, self)
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
		near.target_y = _around(rng, sim.state.anchor_y, REACH)
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


## A fixed column next to the exit's wall: the exit goes where the bird can
## fly straight through the column's gap to it (a moving gap follows the bird).
func blocks_exit(_sim: GameSim, side: int, y: int) -> bool:
	if fixed_lo < 0:
		return false
	var wall := 0 if side == 0 else SimConfig.WORLD_W
	if absi(x - wall) > EXIT_NEAR:
		return false
	var r := SimConfig.BIRD_RADIUS
	if top and y < top_tip() + r:
		return true
	return bottom and y > bottom_tip() - r


func step(_sim: GameSim) -> void:
	if gap_y < target_y:
		gap_y = mini(gap_y + SLIDE, target_y)
	elif gap_y > target_y:
		gap_y = maxi(gap_y - SLIDE, target_y)


## Tip of the hanging rock and of the standing rock.
func top_tip() -> int:
	return gap_y - gap / 2


func bottom_tip() -> int:
	return gap_y + gap / 2


func kills(sim: GameSim) -> bool:
	return (
		(top and sim.bird_touches_rect(x - half_w, 0, x + half_w, top_tip()))
		or (
			bottom
			and sim.bird_touches_rect(x - half_w, bottom_tip(), x + half_w, SimConfig.WORLD_H)
		)
	)


func checksum(h: int) -> int:
	return mix_all(
		h, [x, gap_y, target_y, int(follows), int(top), int(bottom), gap, half_w, fixed_lo]
	)
