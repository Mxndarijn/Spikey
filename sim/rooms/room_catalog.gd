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
	preload("res://sim/rooms/catalog_twists.gd"),
	preload("res://sim/rooms/catalog_boss.gd"),
	preload("res://sim/rooms/catalog_caves.gd"),
	preload("res://sim/rooms/catalog_puzzles.gd"),
]

## The room deck holds this many rooms per word of SimState (deck_lo, deck_hi).
const DECK_BITS := 62
## The bag refills once the rooms still in it weigh less than this share (%)
## of all the rooms that could be picked: a room that weighs little (an easy
## one late in a run) doesn't hold the bag open until it is drawn, so the end
## of a bag is not a run of the lightest rooms. 0 = only once it is empty.
const DECK_REFILL_PCT := 25

static var _all: Array[RoomDef] = []
static var _bosses: Array[int] = []


static func all() -> Array[RoomDef]:
	if _all.is_empty():
		for batch in BATCHES:
			for def: RoomDef in batch.defs():
				_all.append(def)
		RoomPacing.apply(_all)
	return _all


static func release() -> void:
	_all.clear()
	_bosses.clear()


## Indexes of the boss rooms, in catalog order.
static func bosses() -> Array[int]:
	if _bosses.is_empty():
		var list := all()
		for i in list.size():
			if list[i].boss:
				_bosses.append(i)
	return _bosses


## Picks the boss room for a boss portal: one RNG draw among the bosses not
## met yet this run (bit i of `met` is bosses()[i]); all of them once every
## one has been met.
static func pick_boss(rng: SimRng, met: int) -> int:
	var list := bosses()
	var open: Array[int] = []
	for i in list.size():
		if (met >> i) & 1 == 0:
			open.append(i)
	if open.is_empty():
		for i in list.size():
			open.append(i)
	return list[open[rng.next_below(open.size())]]


## The bosses_met bit of boss room `index` (0 for any other room).
static func boss_bit(index: int) -> int:
	var i := bosses().find(index)
	return 0 if i < 0 else 1 << i


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
	if def.weight_at(score) <= 0:
		return false
	return def.season == Seasons.NONE or def.season == season


## Whether room `index` has been drawn from the deck's current bag.
static func drawn(state: SimState, index: int) -> bool:
	if index < DECK_BITS:
		return (state.deck_lo >> index) & 1 == 1
	return (state.deck_hi >> (index - DECK_BITS)) & 1 == 1


## Marks room `index` drawn from the current bag.
static func mark_drawn(state: SimState, index: int) -> void:
	if index < DECK_BITS:
		state.deck_lo |= 1 << index
	else:
		state.deck_hi |= 1 << (index - DECK_BITS)


## Picks the next room from a shuffle bag ("deck"): a room drawn from the bag
## doesn't come back until the bag refills, so every room comes up before
## any repeats (rooms that weigh very little may wait for a later bag:
## DECK_REFILL_PCT). Among the rooms still in the bag the pick is by weight
## at this score (RoomDef.pace); a room unlocked meanwhile joins the bag.
## Never the current room or the open first room, nor a boss, nor one that
## doesn't fit a bird coming out of a portal at state.anchor_y
## (RoomDef.arrival_skip). The deck lives in `state` (deck_lo, deck_hi) and
## only the rooms picked change it, so it is the same for every route: a fork
## never changes which room comes next. On a refill only the current room
## stays drawn. One RNG draw (none if no room fits).
static func pick_next(rng: SimRng, state: SimState, current: int, season: int) -> int:
	var list := all()
	var score := state.score
	# The open first room is only the start: a run never comes back to it.
	var start := first_index()
	var weights: Array[int] = []
	var total := 0
	var left := 0
	for i in list.size():
		var w := 0
		if (
			i != current
			and i != start
			and not list[i].boss
			and allowed(list[i], score, season)
			and list[i].fits_arrival(state.anchor_y)
		):
			w = list[i].weight_at(score)
		weights.append(w)
		total += w
		if not drawn(state, i):
			left += w
	if total == 0:
		return current
	if left == 0 or left * 100 < total * DECK_REFILL_PCT:
		state.deck_lo = 0
		state.deck_hi = 0
		if current >= 0:
			mark_drawn(state, current)
		left = total
	var r := rng.next_below(left)
	for i in list.size():
		if weights[i] > 0 and not drawn(state, i):
			r -= weights[i]
			if r < 0:
				mark_drawn(state, i)
				return i
	return current
