extends Hazard
## Crowded (Filling up): the walls keep their spikes. Every other room draws a
## fresh wall at each bounce; here a wall's spikes are its crowd, and they stay
## in their seats. At each bounce newcomers pick a seat on the wall the bird
## just left (shown walking in, not deadly: that wall has no spikes out) and
## sit down when that wall comes up next. The room starts nearly empty and is
## packed by its exit.
##
## The new wall's free run is still drawn as in every room (RoomRules, near
## the anchor), and anyone seated in it stands up and leaves, so the crowd
## never closes the way through.
##
## Seats come from an RNG seeded from the room seed and the wall's number, so
## the same seed gives the same crowd whatever the player does.
##
## Variants (the room's variant id):
##   classic:  START seats a wall, one newcomer per bounce.
##   lopsided: every newcomer goes to the left wall.
##   storm:    one seat a wall to start, two newcomers per bounce.

const START := 2
const SALT := 0x51C7D2

## Seated spikes per wall (slot masks), left and right.
var seats_left := 0
var seats_right := 0
## Seats picked by the newcomers walking in on each wall (slot masks).
var coming_left := 0
var coming_right := 0
## Whether each wall got its first seats yet.
var started_left := false
var started_right := false
## Steps since the newcomers started walking (for the painter).
var since_pick := 0
var start_seats := START
var newcomers := 1
## Newcomers only ever sit on the left wall (lopsided).
var left_only := false
## The free run the last wall was drawn with (a slot mask): kept clear.
var last_run := 0
## Free slots in a row a wall always keeps (RoomDef.gap).
var keep_run := 4

var _seed := 0
var _rng := SimRng.new()


func _init() -> void:
	kind = "crowd_fill"


func setup(sim: GameSim, _rng_room: SimRng) -> void:
	match sim.room.variant_id():
		"lopsided":
			left_only = true
		"storm":
			start_seats = 1
			newcomers = 2
	keep_run = sim.room.def.gap
	_seed = SimHash.mix(sim.room.rng_seed, SALT)


func step(_sim: GameSim) -> void:
	since_pick += 1


func seats(side: int) -> int:
	return seats_left if side == 0 else seats_right


func coming(side: int) -> int:
	return coming_left if side == 0 else coming_right


## The wall `side` was just drawn as `mask`: it shows its seated crowd
## instead, with the newcomers sat down and the drawn free run cleared.
## Then newcomers pick their seats on the other wall.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	_rng.reseed(SimHash.mix(_seed, sim.room.walls))
	var span := (1 << keep_run) - 1
	var run := RoomRules.longest_gap_mask(mask)
	if sim.wall_run[0] >= 0:
		run = span << sim.wall_run[0]
	var have := seats(side) | coming(side)
	var started := started_left if side == 0 else started_right
	if not started:
		have = _pick(have, run, start_seats)
	# The crowd makes way only when it leaves no free run where this wall's
	# could have been drawn (in reach of the anchor): then the drawn run
	# stands up and leaves.
	var kept := -1
	if sim.wall_run[0] >= 0:
		for start in range(sim.wall_run[1], sim.wall_run[2] + 1):
			if have & (span << start) == 0:
				kept = start
				break
	if kept >= 0:
		run = span << kept
	have &= ~run
	last_run = run
	if side == 0:
		seats_left = have
		coming_left = 0
		started_left = true
	else:
		seats_right = have
		coming_right = 0
		started_right = true
	var other := 1 - side
	if not left_only or other == 0:
		var add := _pick(seats(other) | coming(other), 0, newcomers) & ~seats(other)
		if other == 0:
			coming_left = add & ~seats_left
		else:
			coming_right = add & ~seats_right
	since_pick = 0
	return have


## `taken` with `n` more seats picked, never in `keep_free` and never where
## the wall would lose its last run of RoomDef.gap free slots.
func _pick(taken: int, keep_free: int, n: int) -> int:
	var out := taken
	for i in n:
		var free: Array[int] = []
		for slot in SimConfig.SLOT_COUNT:
			if RoomRules.has_slot(out, slot) or RoomRules.has_slot(keep_free, slot):
				continue
			if RoomRules.longest_gap(out | (1 << slot)) < keep_run:
				continue
			free.append(slot)
		if free.is_empty():
			break
		out |= 1 << free[_rng.next_below(free.size())]
	return out


func checksum(h: int) -> int:
	return mix_all(
		h,
		[
			seats_left,
			seats_right,
			coming_left,
			coming_right,
			int(started_left),
			int(started_right),
			since_pick,
			start_seats,
			newcomers,
			int(left_only),
			keep_run,
			last_run,
			_seed
		]
	)
