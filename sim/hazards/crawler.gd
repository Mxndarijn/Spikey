extends Hazard
## A caterpillar (Caterpillar Crawl; Summer Crab Walk is the same with a skin):
## a chain of round segments walking clockwise round a rectangle inside the
## cage (ceiling, wall, floor, wall). Every segment kills.
##
## A crawler on a wall side stands between the bird and that wall, so the room
## keeps a way past it: no exit is planned where a crawler will be when the
## bird gets there (blocks_exit), and every new wall keeps a spike-free bounce
## spot clear of the crawlers (on_bounce).

const SEGMENTS := 6
const SEG_RADIUS := 10 * SimConfig.SUB
## Distance along the path between segment centres.
const SPACING := 22 * SimConfig.SUB
## Path speed per step.
const SPEED := SimConfig.SUB
## The path rectangle: past the wall spikes, clear of the ceiling and floor.
const LEFT := 60 * SimConfig.SUB
const RIGHT := 300 * SimConfig.SUB
const TOP := 80 * SimConfig.SUB
const BOTTOM := 560 * SimConfig.SUB
const W := RIGHT - LEFT
const H := BOTTOM - TOP
const PERIMETER := 2 * (W + H)
## A crawler starts with its whole body on the ceiling or floor edge, its head
## at least 50 px from the next corner, so it never comes down a wall onto the
## bird right at the start of the room.
const START_SPAN := W - (SEGMENTS - 1) * SPACING - 50 * SimConfig.SUB

## A segment is in the bird's way when it comes this close to it sideways:
## touching, plus a little.
const NEAR_X := SEG_RADIUS + SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB
## Steps before (and after) the bird is at a wall in which it can be that
## close to a segment on that wall's side of the path.
const WALL_WINDOW := (LEFT - SimConfig.BIRD_RADIUS + NEAR_X) / SimConfig.SPEED_X + 1
## A wall slot is covered when a segment in the bird's way is within this of
## its centre: the bird anywhere in the slot would touch it (or nearly).
const SLOT_CLEAR := SimConfig.SLOT_SIZE / 2 + SEG_RADIUS + SimConfig.BIRD_RADIUS + 2 * SimConfig.SUB
## An exit is blocked when a segment in the bird's way is within this of its
## centre: the whole opening stays free.
const EXIT_CLEAR := SimConfig.EXIT_FIT + SEG_RADIUS + SimConfig.BIRD_RADIUS + SimConfig.SUB
## Every new wall keeps this many slots in a row free of spikes and crawlers
## (fewer only if the crawlers leave no such run).
const FREE_RUN := 3
## After a revive the exit is already planned: a crawler that would be in
## front of it starts somewhere else along its path, moved in steps of this,
## at most this many times.
const REVIVE_SHIFT := 16 * SimConfig.SUB
const REVIVE_TRIES := 12
## Further than any distance in the cage.
const FAR := 1 << 30

## 0 starts on the ceiling heading right, 1 on the floor heading left.
var lane := 0
## Path position of the tail at t = 0.
var start := 0
## Segment centres, head first (filled every step for the painter).
var xs: Array[int] = []
var ys: Array[int] = []


func _init(p_lane: int = 0) -> void:
	kind = "crawler"
	lane = p_lane


func setup(sim: GameSim, rng: SimRng) -> void:
	start = rng.next_below(START_SPAN) + lane * (W + H)
	# Only a revive starts the room with an exit already planned or open.
	if sim.state.exit_open or sim.state.exit_preview:
		# Back if the exit is on the wall this crawler walks to first; if it is
		# on the wall behind it (its tail still near that corner), on.
		var move := -REVIVE_SHIFT if sim.state.exit_side == 1 - lane else REVIVE_SHIFT
		for i in REVIVE_TRIES:
			if not _blocks_planned_exit(sim):
				break
			start += move
	xs.resize(SEGMENTS)
	ys.resize(SEGMENTS)
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var tail := start + t * SPEED
	for i in SEGMENTS:
		var s := posmod(tail + (SEGMENTS - 1 - i) * SPACING, PERIMETER)
		xs[i] = path_x(s)
		ys[i] = path_y(s)


## x of path position `s` (0 to PERIMETER, from the top left corner, clockwise).
func path_x(s: int) -> int:
	if s < W:
		return LEFT + s
	if s < W + H:
		return RIGHT
	if s < 2 * W + H:
		return RIGHT - (s - W - H)
	return LEFT


## y of path position `s`.
func path_y(s: int) -> int:
	if s < W:
		return TOP
	if s < W + H:
		return TOP + s - W
	if s < 2 * W + H:
		return BOTTOM
	return BOTTOM - (s - 2 * W - H)


func kills(sim: GameSim) -> bool:
	for i in SEGMENTS:
		if sim.bird_touches_circle(xs[i], ys[i], SEG_RADIUS):
			return true
	return false


## No exit where this crawler will be in the bird's way as it flies in.
func blocks_exit(sim: GameSim, side: int, y: int) -> bool:
	var span := _in_the_way(sim, start, side, t + sim.steps_to_wall(side), 0)
	return y > span[0] - EXIT_CLEAR and y < span[1] + EXIT_CLEAR


## The wall ahead just got its spikes. If the crawlers will cover its free
## slots when the bird gets there, spikes come off the nearest run of slots
## they leave alone, so there is always a spot to bounce on that is free of
## both. The first crawler does this for all of them. A wall with an open exit
## is left as it is (blocks_exit kept the exit clear).
func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	var s := sim.state
	var side := 1 if s.vx > 0 else 0
	if s.exit_open and s.exit_side == side:
		return
	var arrive := t + sim.steps_to_wall(side)
	var covered := 0
	var first := true
	for h in sim.room.hazards:
		if h.kind != kind:
			continue
		if first and h != self:
			return
		first = false
		var from: int = h.start
		var span := _in_the_way(sim, from, side, arrive, WALL_WINDOW)
		for slot in SimConfig.SLOT_COUNT:
			var cy := SimConfig.slot_center_y(slot)
			if cy > span[0] - SLOT_CLEAR and cy < span[1] + SLOT_CLEAR:
				covered |= 1 << slot
	if covered == 0:
		return
	var mask := s.right_spikes if side == 1 else s.left_spikes
	var run := _best_run(mask, covered, s.y)
	if run & mask == 0:
		return
	if side == 1:
		s.right_spikes = mask & ~run
	else:
		s.left_spikes = mask & ~run


## The run of FREE_RUN slots (as a mask) the crawlers leave alone that is best
## for a bird at height `bird_y`: within its reach, then with the fewest
## spikes to take off, then nearest. Shorter runs if there is none that long;
## 0 if every slot is covered.
func _best_run(mask: int, covered: int, bird_y: int) -> int:
	for want in range(FREE_RUN, 0, -1):
		var best := 0
		var best_rank := -1
		for slot in SimConfig.SLOT_COUNT - want + 1:
			var run := ((1 << want) - 1) << slot
			if covered & run != 0:
				continue
			var centre := SimConfig.slot_center_y(slot) + (want - 1) * SimConfig.SLOT_SIZE / 2
			var away := absi(centre - bird_y)
			var spikes := 0
			for i in want:
				if RoomRules.has_slot(mask, slot + i):
					spikes += 1
			var rank := away + spikes * SimConfig.WORLD_H
			if away > RoomRules.GAP_REACH:
				rank += SimConfig.SLOT_COUNT * SimConfig.WORLD_H
			if best_rank < 0 or rank < best_rank:
				best_rank = rank
				best = run
		if best != 0:
			return best
	return 0


## Whether this crawler would be in front of the exit(s) already planned.
func _blocks_planned_exit(sim: GameSim) -> bool:
	var s := sim.state
	if blocks_exit(sim, s.exit_side, s.exit_a_y):
		return true
	return s.exit_b_kind != SimState.ExitKind.NORMAL and blocks_exit(sim, s.exit_side, s.exit_b_y)


## The heights [lowest y, highest y] of the segments of a crawler (tail at path
## position `from` at t = 0) that are in the way of a bird reaching wall `side`
## at room step `arrive`: those it comes within NEAR_X of sideways in the
## WALL_WINDOW steps before, and the `after` steps after as it flies back.
## [FAR, -FAR] when none is.
func _in_the_way(sim: GameSim, from: int, side: int, arrive: int, after: int) -> PackedInt32Array:
	var r := SimConfig.BIRD_RADIUS
	var wall := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var inward := -SimConfig.SPEED_X if side == 1 else SimConfig.SPEED_X
	var lo := FAR
	var hi := -FAR
	for d in range(-WALL_WINDOW, after + 1):
		var bird_x := wall + inward * absi(d)
		var tail := from + (arrive + d) * SPEED
		for i in SEGMENTS:
			var s := posmod(tail + i * SPACING, PERIMETER)
			if absi(path_x(s) - bird_x) < NEAR_X:
				var y := path_y(s)
				lo = mini(lo, y)
				hi = maxi(hi, y)
	return PackedInt32Array([lo, hi])


func checksum(h: int) -> int:
	var out := mix_all(h, [lane, start])
	for i in SEGMENTS:
		out = mix_all(out, [xs[i], ys[i]])
	return out
