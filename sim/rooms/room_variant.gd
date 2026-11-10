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
