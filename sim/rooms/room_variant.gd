class_name RoomVariant
extends RefCounted
## One way a room kind can turn out. A RoomDef with variants draws one from the
## RNG every time the room starts (Bumper Cloud: one cloud or two; Tide Spikes:
## normal, big or small spikes). Gameplay data, like RoomDef.

## Squeeze Box: how the walls move. POINTS: both step in per point (the
## room's own rule); LEFT: only the left wall, in bigger steps; BREATHE: both
## slide in and back out on a slow loop, whatever the score.
enum Squeeze { POINTS, LEFT, BREATHE }

var id := ""
## Wall spike size (depth and base) as a fraction of a normal spike.
var spike_num := 1
var spike_den := 1
## Added to the room's spike count per wall (may be negative).
var extra_spikes := 0
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


func with(p_hazards: Array[Callable]) -> RoomVariant:
	hazards = p_hazards
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
