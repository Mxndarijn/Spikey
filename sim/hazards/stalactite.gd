extends Hazard
## Stalactite Run: a rock column with a stalactite hanging from the top and a
## stalagmite standing from the bottom, leaving a gap. The rock kills.
##
## A column is fixed or scheduled, so the room never reads the bird:
## - fixed (fixed_lo >= 0): its gap sits round the bird's hop where it came in
##   (clamped to fixed_lo..fixed_hi) for the whole room;
## - scheduled (scheduled): its gap slides (SLIDE per step, drawn as it moves)
##   to the next height of a list drawn when the room starts, each time the
##   bird bounces off the far wall from it (heading its way), and stays on the
##   list's last height (the exit's lane, blocks_exit) from the bounce before
##   the exit opens on.
## Variants: a column can lose its top or bottom rock (top, bottom), have a
## smaller or bigger gap (gap) or be thinner (half_w).

## Gap between the two rocks (tip to tip).
const GAP := 150 * SimConfig.SUB
## Width of the rock column.
const HALF_W := 22 * SimConfig.SUB
## Range of a scheduled gap's centre.
const GAP_MIN := 150 * SimConfig.SUB
const GAP_MAX := 490 * SimConfig.SUB
## A scheduled gap's next height is within this of the one before, and every
## one within SCHED_REACH of where it starts (round the entry column's gap),
## so the bird can always fly from one gap to the other.
const MAX_STEP := 60 * SimConfig.SUB
const SCHED_REACH := 100 * SimConfig.SUB
## No wall spike within this of the gap next to the wall ahead.
const WALL_CLEAR := 70 * SimConfig.SUB
## How fast the gap slides to its new height, per step.
const SLIDE := 3 * SimConfig.SUB
## A fixed gap sits this far above where the bird came in: a bird holding its
## height hops up to about 60 px over it, so this is the middle of its hop.
const HOP_MID := 30 * SimConfig.SUB
## A fixed column this close to a wall keeps that wall's exit inside its gap;
## any other fixed column keeps it within FIXED_REACH past its tip (the bird
## crosses that far before the exit, and must get back over it each lap).
const EXIT_NEAR := 120 * SimConfig.SUB
const FIXED_REACH := 120 * SimConfig.SUB

## Column centre, sub-units.
var x := 0
## Gap centre now, and where it is sliding to.
var gap_y := 0
var target_y := 0
## Follows the column before it in the room: only the leader keeps the wall
## ahead clear (fixed columns).
var follows := false
## Which rocks the column has: hanging from the top, standing from the bottom.
var top := true
var bottom := true
## Gap between the tips, and half the column's width.
var gap := GAP
var half_w := HALF_W
## A fixed gap: its centre range (sub-units), or -1.
var fixed_lo := -1
var fixed_hi := -1
## A scheduled gap: its heights (drawn at setup, the last one the exit's lane)
## and how many of them it has slid to.
var scheduled := false
## Where a scheduled gap starts (its recipe's height round the arrival band, past
## GAP_MIN..GAP_MAX if the band is), or -1: round the bird's hop.
var start_y := -1
var schedule := PackedInt32Array()
var slides := 0


func _init(p_x: int = 0, p_follows: bool = false) -> void:
	kind = "stalactite"
	x = p_x
	follows = p_follows


func setup(sim: GameSim, rng: SimRng) -> void:
	if fixed_lo >= 0:
		gap_y = clampi(FairLanes.entry_y(sim) - HOP_MID, fixed_lo, fixed_hi)
		target_y = gap_y
		return
	# A scheduled gap starts round the bird's hop where it came in.
	gap_y = clampi(FairLanes.entry_y(sim) - HOP_MID, GAP_MIN, GAP_MAX)
	if start_y >= 0:
		gap_y = start_y
	target_y = gap_y
	if scheduled:
		_draw_schedule(sim, rng)


## The heights the gap slides to, one per bounce off the left wall: a walk of
## steps up to MAX_STEP from the start. From the slide that comes with the bounce
## the exit's ghost shows on (or the one before) the gap stays on the last
## height: the exit plans its lane there (blocks_exit).
func _draw_schedule(sim: GameSim, rng: SimRng) -> void:
	schedule = PackedInt32Array()
	slides = 0
	# Bounces until the ghost shows (one point before the exit). The first
	# bounce is off the wall by this column, so every second one is off the
	# far wall.
	var to_ghost := maxi(sim.next_exit_score() - 1 - sim.state.score, 0)
	var park := maxi((to_ghost + 1) / 2 - 1, 0)
	var y := gap_y
	var lo := maxi(mini(GAP_MIN, gap_y), gap_y - SCHED_REACH)
	var hi := mini(maxi(GAP_MAX, gap_y), gap_y + SCHED_REACH)
	for i in park + 1:
		y = _within(rng, y, MAX_STEP, lo, hi)
		schedule.append(y)


## A fixed column keeps the way out of its gap open. A scheduled one slides on
## to its next height when the bird has bounced off the far wall from it (it
## is far away then), and keeps the wall by it clear round its gap.
func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if follows:
		return
	if fixed_lo >= 0:
		_clear_wall_ahead(sim, self)
		return
	if not scheduled or (sim.state.vx > 0) != (_near_wall() == 1):
		return
	target_y = schedule[mini(slides, schedule.size() - 1)]
	slides += 1
	_clear_wall_ahead(sim, self)


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


## A height within `spread` of `center`, inside lo..hi.
static func _within(rng: SimRng, center: int, spread: int, lo: int, hi: int) -> int:
	var a := maxi(lo, center - spread)
	var b := mini(hi, center + spread)
	if a > b:
		return clampi(center, lo, hi)
	return a + rng.next_below(b - a + 1)


## The wall this column stands nearer: 0 left, 1 right.
func _near_wall() -> int:
	return 1 if x > SimConfig.WORLD_W / 2 else 0


## A fixed column next to the exit's wall: the exit goes where the bird can
## fly straight through the column's gap to it. A scheduled column: an exit on
## the wall by it goes where the bird can fly through the gap's last height
## (it parks there before the exit opens).
func blocks_exit(_sim: GameSim, side: int, y: int) -> bool:
	var r := SimConfig.BIRD_RADIUS
	if scheduled:
		if side != _near_wall() or schedule.is_empty():
			return false
		var lane := schedule[schedule.size() - 1]
		return absi(y - lane) > gap / 2 - r
	if fixed_lo < 0:
		return false
	var wall := 0 if side == 0 else SimConfig.WORLD_W
	if absi(x - wall) > EXIT_NEAR:
		return (top and y < top_tip() - FIXED_REACH) or (bottom and y > bottom_tip() + FIXED_REACH)
	if top and y < gap_y - gap / 2 + r:
		return true
	return bottom and y > gap_y + gap / 2 - r


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
	var out := mix_all(
		h, [x, gap_y, target_y, int(follows), int(top), int(bottom), gap, half_w, fixed_lo]
	)
	if scheduled:
		out = mix_all(out, [slides] + Array(schedule))
	return out
