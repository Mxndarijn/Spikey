class_name RoomVariant
extends RefCounted
## One way a room kind can turn out. A RoomDef with variants draws one from the
## RNG every time the room starts (Bumper Cloud: one cloud or two; Tide Spikes:
## normal, big or small spikes). Gameplay data, like RoomDef.

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


## Whether this variant can be drawn for a bird coming out of a portal at `y`.
func fits_arrival(y: int) -> bool:
	for i in range(0, arrival_skip.size(), 2):
		if y >= arrival_skip[i] and y < arrival_skip[i + 1]:
			return false
	return true
