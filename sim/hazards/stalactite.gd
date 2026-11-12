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
## After a bounce, the column the bird meets first keeps its gap (it is too
## close to the wall to move fairly; a lone column, and both once the exit
## shows, move within REACH of the anchor), and the other column moves toward
## the anchor, within MAX_STEP of the first, so there is always a way through.
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
## How fast an arrival opening (open_top, open_bottom) closes, per step.
const CLOSE := 2 * SimConfig.SUB

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
## Generated variants, out of a portal: the gap opens this much further up
## and down (sub-units) so a bird holding its height anywhere in the exit
## comes through, until room step `open_until`, then closes back at CLOSE per
## step (open_for_arrival). The tips include it, so it is drawn as it kills.
var open_top := 0
var open_bottom := 0
var open_until := 0


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
		# The near column is about 20 steps from the wall: too close to move
		# after the bounce for a player who reacts in about 1 s. With a partner
		# it keeps its gap (the bird came through it on the way to the wall),
		# except once the exit (or its ghost) shows, when both steer to it; the
		# draw stays, so the RNG order does too.
		var drawn := _around(rng, sim.state.anchor_y, REACH)
		if far == null or sim.state.exit_open or sim.state.exit_preview:
			near.target_y = drawn
		# An arrival opening (generated variants) is laid out for the gap as it
		# is: the gap stays put while it is open (the draws are still made).
		if near.open_until > t:
			near.target_y = near.gap_y
	if far != null:
		# The far column walks toward the anchor (which steers to the exit),
		# within MAX_STEP of the near one.
		var n: int = near.target_y
		far.target_y = clampi(
			_around(rng, sim.state.anchor_y, MAX_STEP), n - MAX_STEP, n + MAX_STEP
		)
		if far.open_until > t:
			far.target_y = far.gap_y
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
	# The gap without an arrival opening: that closes again.
	var r := SimConfig.BIRD_RADIUS
	if top and y < gap_y - gap / 2 + r:
		return true
	return bottom and y > gap_y + gap / 2 - r


func step(_sim: GameSim) -> void:
	if gap_y < target_y:
		gap_y = mini(gap_y + SLIDE, target_y)
	elif gap_y > target_y:
		gap_y = maxi(gap_y - SLIDE, target_y)
	if t > open_until:
		open_top = maxi(open_top - CLOSE, 0)
		open_bottom = maxi(open_bottom - CLOSE, 0)


## Generated variants, out of a portal: opens the gap round the band a bird
## holding its height anywhere in the exit sweeps (VariantParams.hold_top /
## hold_bottom) while it flies past this column, there and back
## (FairLanes.arrival_x for OPEN_PATH_TICKS steps), and keeps it open, the gap
## held still, until it is past the last time. No RNG.
func open_for_arrival(sim: GameSim, p: VariantParams) -> void:
	if not p.arriving:
		return
	var reach := half_w + SimConfig.BIRD_RADIUS
	var last := -1
	for k in FairLanes.OPEN_PATH_TICKS:
		if absi(FairLanes.arrival_x(sim, k + 1) - x) < reach:
			last = k + 1
	if last < 0:
		return
	open_until = last
	if top:
		open_top = maxi(gap_y - gap / 2 - p.hold_top(), 0)
	if bottom:
		open_bottom = maxi(p.hold_bottom() - (gap_y + gap / 2), 0)


## Tip of the hanging rock and of the standing rock.
func top_tip() -> int:
	return gap_y - gap / 2 - open_top


func bottom_tip() -> int:
	return gap_y + gap / 2 + open_bottom


func kills(sim: GameSim) -> bool:
	return (
		(top and sim.bird_touches_rect(x - half_w, 0, x + half_w, top_tip()))
		or (
			bottom
			and sim.bird_touches_rect(x - half_w, bottom_tip(), x + half_w, SimConfig.WORLD_H)
		)
	)


func checksum(h: int) -> int:
	var out := mix_all(
		h, [x, gap_y, target_y, int(follows), int(top), int(bottom), gap, half_w, fixed_lo]
	)
	if open_top != 0 or open_bottom != 0 or open_until != 0:
		out = mix_all(out, [open_top, open_bottom, open_until])
	return out
