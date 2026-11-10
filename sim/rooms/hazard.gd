class_name Hazard
extends RefCounted
## One thing in a room besides the wall spikes: something that kills, bounces,
## carries or pays the bird. Each room kind builds its hazards from RoomDef.
##
## Rules for subclasses (they are gameplay, so they replay on the server):
## - Integer sub-units only; motion comes from `t` (steps since the room began)
##   and values drawn from the room's SimRng in setup()/on_bounce().
## - Draw from the RNG in a fixed order. Changing it is a gameplay change.
## - Put every changing int in checksum().
## - Public fields are what its painter (game/run/painters/<kind>_painter.gd)
##   draws. Looks (a room's skin) live in game/, never here.

## Painter key, e.g. "block". One painter per kind.
var kind := ""
## False once the hazard is gone (a coin taken, a ball on the floor).
var alive := true
## Steps since the room started.
var t := 0


## Called once when the room starts.
func setup(_sim: GameSim, _rng: SimRng) -> void:
	pass


## Advances one sim step (before the bird moves).
func step(_sim: GameSim) -> void:
	pass


## True when the bird touches a deadly part.
func kills(_sim: GameSim) -> bool:
	return false


## Safe effects after the bird moved: bounce, carry, push, pickups.
func touch(_sim: GameSim) -> void:
	pass


## A wall just got new spikes (`mask`, 0 = left, 1 = right): return the mask
## it should have, so the hazard can keep a spot to bounce on clear of itself.
## Called for every hazard, in order, before the room's own wall rules (tide,
## blink) see the mask. No RNG draws here.
func adjust_wall(_sim: GameSim, _side: int, mask: int) -> int:
	return mask


## The bird bounced off a side wall (for hazards that reshuffle per bounce).
## The new wall's spikes are already set; change them in adjust_wall().
func on_bounce(_sim: GameSim, _rng: SimRng) -> void:
	pass


## The player tapped.
func on_flap(_sim: GameSim) -> void:
	pass


## True if an exit at height `y` on wall `side` (0 = left, 1 = right) could not
## be reached past this hazard. Asked when an exit is planned (the bird has just
## bounced; GameSim.steps_to_wall(side) tells when it gets there), so the exit
## goes somewhere else. No RNG draws here.
func blocks_exit(_sim: GameSim, _side: int, _y: int) -> bool:
	return false


## True if this hazard makes the ceiling (top) or floor safe where the bird is;
## it may bounce the bird too.
func guards_edge(_sim: GameSim, _top: bool) -> bool:
	return false


func checksum(h: int) -> int:
	return h


## Mixes several ints into a checksum (helper for subclasses).
static func mix_all(h: int, values: Array) -> int:
	var out := h
	for v: int in values:
		out = SimHash.mix(out, v)
	return out
