class_name RoomVariant
extends RefCounted
## One way a room kind can turn out. A RoomDef with variants draws one from the
## RNG every time the room starts (Bumper Cloud: one cloud or two; Tide Spikes:
## normal, big or small spikes). Gameplay data, like RoomDef.
##
## A variant is STATIC (its hazards are fixed factories, `hazards`, as hand
## made) or GENERATED (`recipe` builds its layout when the room starts, from
## the room RNG and VariantParams: the planned entry height and the score).
## A generated layout is checked (VariantCheck) and, if it fails, built again
## from the next draws, up to GENERATE_TRIES times; the last try is the
## recipe's safe fallback (VariantParams.fallback), never checked. So it fits
## every arrival height and needs no arrival_skip. Floating Isles is the
## reference generated variant (docs/ARCHITECTURE.md, "Generated variants").

enum Kind { STATIC, GENERATED }

## Squeeze Box: how the walls move. POINTS: both step in per point (the
## room's own rule); LEFT: only the left wall, in bigger steps; BREATHE: both
## slide in and back out on a slow loop, whatever the score.
enum Squeeze { POINTS, LEFT, BREATHE }

## Tries of a generated layout, the last one the fallback.
const GENERATE_TRIES := 8

var id := ""
var kind := Kind.STATIC
## GENERATED: func(p: VariantParams) -> void that builds the layout into the
## room with p.add(), drawing from p.rng.
var recipe := Callable()
## GENERATED: the check must keep the bird off even safe bodies (bubbles).
var avoid_touch := false
## GENERATED: moving steps the check holds the bird's height (0 =
## VariantCheck.HOLD_STEPS). Longer for a hazard whose first danger comes
## after the reading time (the first gift in Gift Stack).
var hold_steps := 0
## GENERATED: how far from the planned height the arrival checks put the bird
## (0 = SimConfig.EXIT_FIT, the whole exit). A room allowed to be a little
## tighter than the whole exit (Cave Tunnel) checks a narrower band; a bird
## coming through the exit's very edge then has to react in its first second.
var arrival_spread := 0
## Wall spike size (depth and base) as a fraction of a normal spike.
var spike_num := 1
var spike_den := 1
## Added to the room's spike count per wall (may be negative).
var extra_spikes := 0
## Tide Spikes: how far a sliding spike reaches at high tide, as a fraction of
## this variant's still spike (3/2; Tide big 9/4, half as far again).
var tide_num := 3
var tide_den := 2
## Extra hazard factories, built after the room's own.
var hazards: Array[Callable] = []
## Out of a portal this variant isn't drawn when the bird comes in at a height
## in one of these ranges (sub-units, from and to in pairs), like
## RoomDef.arrival_skip. Empty = any height.
var arrival_skip := PackedInt32Array()
## Lopsided: added to the left wall's spike count and taken off the right's.
var lean := 0
var squeeze := Squeeze.POINTS
## Blink Walls: steps between pattern swaps (0 = RoomRuntime.BLINK_PERIOD).
## A faster blink keeps one free run in both patterns, so a lane stays open.
var blink_period := 0
## Gravity turns round at every wall bounce (Flip-flop).
var flip_flop := false


func _init(p_id: String = "") -> void:
	id = p_id


func sized(num: int, den: int, p_extra_spikes: int) -> RoomVariant:
	spike_num = num
	spike_den = den
	extra_spikes = p_extra_spikes
	return self


## Tide Spikes: sliding spikes reach `num` / `den` of a still spike.
func tide_reach(num: int, den: int) -> RoomVariant:
	tide_num = num
	tide_den = den
	return self


func with(p_hazards: Array[Callable]) -> RoomVariant:
	hazards = p_hazards
	return self


## Makes this a GENERATED variant built by `p_recipe` (see `recipe`).
func generated(
	p_recipe: Callable, p_avoid_touch: bool = false, p_hold_steps: int = 0
) -> RoomVariant:
	kind = Kind.GENERATED
	recipe = p_recipe
	avoid_touch = p_avoid_touch
	hold_steps = p_hold_steps
	return self


## Checks arrivals within `p_spread` of the planned height (arrival_spread).
func checked_within(p_spread: int) -> RoomVariant:
	arrival_spread = p_spread
	return self


func skipping(p_ranges: PackedInt32Array) -> RoomVariant:
	arrival_skip = p_ranges
	return self


func leaning(p_lean: int) -> RoomVariant:
	lean = p_lean
	return self


func squeezing(p_mode: Squeeze) -> RoomVariant:
	squeeze = p_mode
	return self


func blinking(p_period: int) -> RoomVariant:
	blink_period = p_period
	return self


func flipping() -> RoomVariant:
	flip_flop = true
	return self


## Whether this variant can be drawn for a bird coming out of a portal at `y`.
func fits_arrival(y: int) -> bool:
	for i in range(0, arrival_skip.size(), 2):
		if y >= arrival_skip[i] and y < arrival_skip[i + 1]:
			return false
	return true
