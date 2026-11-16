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
## A room picked doesn't come back while it is among the last RECENT_ROOMS
## picks, whatever its tier or variant and across bags (the user, 2026-11-16:
## more variety). Bosses and the open first room are never picked, so they
## don't count. If every room that fits is that recent (a small pool, early or
## at a fork), the window shrinks for that pick only: the oldest picks go first.
const RECENT_ROOMS := 8
## Bits per room in SimState.recent_rooms: room index + 1 (0 = none yet).
const RECENT_BITS := 7

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


## The room picked `k` picks ago (0 = the last one), or -1 if none.
static func recent(state: SimState, k: int) -> int:
	return ((state.recent_rooms >> (k * RECENT_BITS)) & ((1 << RECENT_BITS) - 1)) - 1


## Whether room `index` is among the last `n` picks.
static func is_recent(state: SimState, index: int, n: int) -> bool:
	for k in n:
		if recent(state, k) == index:
			return true
	return false


## Puts room `index` first in the last picks (the oldest one drops out).
static func remember(state: SimState, index: int) -> void:
	var keep := (1 << (RECENT_BITS * (RECENT_ROOMS - 1))) - 1
	state.recent_rooms = ((state.recent_rooms & keep) << RECENT_BITS) | (index + 1)


## How many of the last picks to keep out: RECENT_ROOMS, or fewer if that
## leaves no room of `weights` (the largest window that leaves one).
static func recent_window(state: SimState, weights: Array[int]) -> int:
	var n := RECENT_ROOMS
	while n > 0:
		var open := 0
		for i in weights.size():
			if not is_recent(state, i, n):
				open += weights[i]
		if open > 0:
			return n
		n -= 1
	return 0


## Picks the next room from a shuffle bag ("deck"): a room drawn from the bag
## doesn't come back until the bag refills, so every room comes up before
## any repeats (rooms that weigh very little may wait for a later bag:
## DECK_REFILL_PCT), and never while it is among the last picks
## (RECENT_ROOMS, recent_window). Among the rooms left the pick is by weight
## at this score (RoomDef.pace); a room unlocked meanwhile joins the bag.
## Never the current room or the open first room, nor a boss, nor one that
## doesn't fit a bird coming out of a portal at state.anchor_y
## (RoomDef.arrival_skip), nor one with no room for a fork's two exits when its
## exit will be a fork (RoomDef.hosts_fork). The deck and the last picks live
## in `state` (deck_lo, deck_hi, recent_rooms) and only the rooms picked change
## them, so they are the same for every route: a fork never changes which room
## comes next. The bag refills by the weights before the last picks are kept
## out (so it refills as often as without them), or when only recent rooms are
## left in it; on a refill only the current room stays drawn. One RNG draw
## (none if no room fits).
static func pick_next(rng: SimRng, state: SimState, current: int, season: int) -> int:
	var list := all()
	var score := state.score
	# The open first room is only the start: a run never comes back to it.
	var start := first_index()
	var every := SimConfig.POINTS_PER_ROOM
	var fork := ExitPlanner.fork_at((score / every + 1) * every)
	var weights: Array[int] = []
	var total := 0
	var bag_left := 0
	for i in list.size():
		var w := 0
		if (
			i != current
			and i != start
			and not list[i].boss
			and allowed(list[i], score, season)
			and list[i].fits_arrival(state.anchor_y)
			and (list[i].hosts_fork or not fork)
		):
			w = list[i].weight_at(score)
		weights.append(w)
		total += w
		if not drawn(state, i):
			bag_left += w
	if total == 0:
		return current
	var n := recent_window(state, weights)
	var open := 0
	var left := 0
	for i in list.size():
		if is_recent(state, i, n):
			weights[i] = 0
		open += weights[i]
		if not drawn(state, i):
			left += weights[i]
	if left == 0 or bag_left * 100 < total * DECK_REFILL_PCT:
		state.deck_lo = 0
		state.deck_hi = 0
		if current >= 0:
			mark_drawn(state, current)
		left = open
	var r := rng.next_below(left)
	for i in list.size():
		if weights[i] > 0 and not drawn(state, i):
			r -= weights[i]
			if r < 0:
				mark_drawn(state, i)
				remember(state, i)
				return i
	return current
