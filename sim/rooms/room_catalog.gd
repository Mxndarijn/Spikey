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
]

const CALM_GROUPS: Array[String] = ["starter", "mid", "bonus", "seasonal"]
const WILD_GROUPS: Array[String] = ["mid", "late", "seasonal"]

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


## Pick weight of a room on a fork route (0 = not on this route). Calm leads to
## starter, mid, bonus and seasonal rooms (bonus twice as likely); Wild to mid,
## late and seasonal rooms (late twice as likely).
static func route_weight(def: RoomDef, route: int) -> int:
	match route:
		SimState.ExitKind.CALM:
			if def.group not in CALM_GROUPS:
				return 0
			return def.weight * 2 if def.group == "bonus" else def.weight
		SimState.ExitKind.WILD:
			if def.group not in WILD_GROUPS:
				return 0
			return def.weight * 2 if def.group == "late" else def.weight
	return def.weight


## Picks the next room by weight among the allowed ones on the route, never the
## current one or the open first room, nor one that doesn't fit a bird coming
## out of a portal at `arrival_y` (RoomDef.arrival_skip). If the route allows
## nothing yet, any allowed room is fine.
## One RNG draw (none if only one room fits).
static func pick_next(
	rng: SimRng,
	current: int,
	score: int,
	season: int,
	route: int = SimState.ExitKind.NORMAL,
	arrival_y: int = SimConfig.WORLD_H
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
			w = route_weight(list[i], route)
		weights.append(w)
		total += w
	if total == 0 and route != SimState.ExitKind.NORMAL:
		return pick_next(rng, current, score, season, SimState.ExitKind.NORMAL, arrival_y)
	if total == 0:
		return current
	var r := rng.next_below(total)
	for i in list.size():
		r -= weights[i]
		if r < 0 and weights[i] > 0:
			return i
	return current
