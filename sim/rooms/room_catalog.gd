class_name RoomCatalog
extends RefCounted
## Every room kind, in a fixed order (the order is part of the rules: the
## RNG picks by index), and the pick of the next room.
##
## Rooms come in batches, each in its own file returning `defs()`, so new rooms
## are added without touching the others. Append new batches at the end: putting
## one in the middle changes every later index, which is a gameplay change.

const BATCHES: Array[Script] = [
	preload("res://sim/rooms/catalog_core.gd"),
	preload("res://sim/rooms/catalog_motion.gd"),
	preload("res://sim/rooms/catalog_machines.gd"),
	preload("res://sim/rooms/catalog_sky.gd"),
	preload("res://sim/rooms/catalog_seasonal.gd"),
	preload("res://sim/rooms/catalog_combo.gd"),
	preload("res://sim/rooms/catalog_twists.gd"),
]

static var _all: Array[RoomDef] = []


static func all() -> Array[RoomDef]:
	if _all.is_empty():
		for batch in BATCHES:
			for def: RoomDef in batch.defs():
				_all.append(def)
	return _all


static func release() -> void:
	_all.clear()


## The room every run starts in.
static func first_index() -> int:
	return index_of("open")


static func index_of(id: String) -> int:
	var list := all()
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


static func find(id: String) -> RoomDef:
	var i := index_of(id)
	return all()[i] if i >= 0 else null


## True if the room may show up at this score in this season.
static func allowed(def: RoomDef, score: int, season: int) -> bool:
	if def.from_score > score:
		return false
	return def.season == Seasons.NONE or def.season == season


## Picks the next room by weight among the allowed ones, never the current one
## or the open first room, nor one that doesn't fit a bird coming out of a
## portal at `arrival_y` (RoomDef.arrival_skip). The same for every route: a
## fork never changes which room comes next.
## One RNG draw (none if only one room fits).
static func pick_next(
	rng: SimRng, current: int, score: int, season: int, arrival_y: int = SimConfig.WORLD_H
) -> int:
	var list := all()
	# The open first room is only the start: a run never comes back to it.
	var start := first_index()
	var weights: Array[int] = []
	var total := 0
	for i in list.size():
		var w := 0
		var fits := list[i].fits_arrival(arrival_y)
		if i != current and i != start and fits and allowed(list[i], score, season):
			w = list[i].weight
		weights.append(w)
		total += w
	if total == 0:
		return current
	var r := rng.next_below(total)
	for i in list.size():
		r -= weights[i]
		if r < 0 and weights[i] > 0:
			return i
	return current
