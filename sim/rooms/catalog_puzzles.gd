extends RefCounted
## Puzzle rooms: rooms with their own way to score. Order is part of the rules
## (see RoomCatalog); this batch is last, so its rooms come after every other.

const ButtonPair := preload("res://sim/hazards/button_pair.gd")


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	# Buttons: a button in the ceiling and one in the floor. Press the lit one
	# (the top first), then the other, in turn; only presses score, never wall
	# bounces. Where each sits on its line is drawn at room start. Variants:
	# classic (wide buttons); slim (narrower); apart (slim, the bottom one in
	# the other half of the room).
	var buttons := RoomDef.new("buttons", "mid", 30)
	buttons.bounce_points = false
	buttons.max_spikes = 5
	buttons.hazards.append(func() -> Hazard: return ButtonPair.new())
	buttons.variants = [
		RoomVariant.new("classic"),
		RoomVariant.new("slim"),
		RoomVariant.new("apart"),
	]
	out.append(buttons)
	return out
