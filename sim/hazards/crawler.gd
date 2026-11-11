extends Hazard
## A caterpillar (Caterpillar Crawl; Summer Crab Walk is the same with a skin):
## a chain of round segments walking clockwise round a rectangle inside the
## cage (ceiling, wall, floor, wall). Every segment kills.
##
## A crawler on a wall side stands between the bird and that wall, so the room
## keeps a way past it: no exit is planned where a crawler will be when the
## bird gets there (blocks_exit), and every new wall keeps a spike-free bounce
## spot clear of the crawlers (adjust_wall).
##
## Variants: a swarm of four small crawlers, two on the ceiling and two on the
## floor, each pair walking one behind the other (swarm, trailing); two
## shorter crawlers at double speed (sprinters).

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
## (start_span: quicker crawlers start further back.)
const CORNER_CLEAR := 50 * SimConfig.SUB

## Swarm: small crawlers, and the gap from a leader's tail to the head of the
## crawler trailing it.
const SWARM_SEGMENTS := 4
const SWARM_RADIUS := 7 * SimConfig.SUB
const SWARM_SPACING := 15 * SimConfig.SUB
const SWARM_GAP := 50 * SimConfig.SUB
## Sprinters: twice the speed, one segment shorter.
const SPRINT_SEGMENTS := 5
const SPRINT_SPEED := 2 * SimConfig.SUB

## Every new wall keeps this many slots in a row free of spikes and crawlers
## (fewer only if the crawlers leave no such run).
const FREE_RUN := 3
## Further than any distance in the cage.
const FAR := 1 << 30

## 0 starts on the ceiling heading right, 1 on the floor heading left.
var lane := 0
## Path position of the tail at t = 0.
var start := 0
## Its shape and speed (the consts are the classic crawler).
var segments := SEGMENTS
var seg_radius := SEG_RADIUS
var spacing := SPACING
var speed := SPEED
## Path length kept free behind its tail on its starting edge, for a crawler
## trailing it.
var reserve := 0
## Walks behind the crawler before it in the room on the same lane.
var trails := false
## Segment centres, head first (filled every step for the painter).
var xs: Array[int] = []
var ys: Array[int] = []


func _init(p_lane: int = 0) -> void:
	kind = "crawler"
	lane = p_lane


## Makes this a small swarm crawler that leaves room behind it for another.
func swarm() -> Hazard:
	segments = SWARM_SEGMENTS
	seg_radius = SWARM_RADIUS
	spacing = SWARM_SPACING
	reserve = trail_offset()
	return self


## Makes this a small swarm crawler walking behind the one before it.
func trailing() -> Hazard:
	swarm()
	reserve = 0
	trails = true
	return self


## Makes this a quick, shorter crawler.
func sprinter() -> Hazard:
	segments = SPRINT_SEGMENTS
	speed = SPRINT_SPEED
	return self


## Body length, tail centre to head centre.
func body() -> int:
	return (segments - 1) * spacing


## How far behind a leader's tail a trailing crawler's tail starts.
func trail_offset() -> int:
	return body() + SWARM_GAP


## Room on its starting edge for the tail: the head stays CORNER_CLEAR (more
## when quick) from the next corner, and `reserve` stays free behind it.
func start_span() -> int:
	return W - body() - CORNER_CLEAR * speed / SPEED - reserve


## A segment is in the bird's way when it comes this close to it sideways:
## touching, plus a little.
func near_x() -> int:
	return seg_radius + SimConfig.BIRD_RADIUS + 8 * SimConfig.SUB


## Steps before (and after) the bird is at a wall in which it can be that
## close to a segment on that wall's side of the path.
func wall_window() -> int:
	return (LEFT - SimConfig.BIRD_RADIUS + near_x()) / SimConfig.SPEED_X + 1


## A wall slot is covered when a segment in the bird's way is within this of
## its centre: the bird anywhere in the slot would touch it (or nearly).
func slot_clear() -> int:
	return SimConfig.SLOT_SIZE / 2 + seg_radius + SimConfig.BIRD_RADIUS + 2 * SimConfig.SUB


## An exit is blocked when a segment in the bird's way is within this of its
## centre: the whole opening stays free.
func exit_clear() -> int:
	return SimConfig.EXIT_FIT + seg_radius + SimConfig.BIRD_RADIUS + SimConfig.SUB


func setup(sim: GameSim, rng: SimRng) -> void:
	var leader := _leader(sim) if trails else null
	if leader != null:
		start = leader.start - trail_offset()
	else:
		start = reserve + rng.next_below(start_span()) + lane * (W + H)
	xs.resize(segments)
	ys.resize(segments)
	_place()


## The crawler before this one in the room on the same lane that it trails.
func _leader(sim: GameSim) -> Hazard:
	var out: Hazard = null
	for h in sim.room.hazards:
		if h == self:
			break
		if h.kind == kind and h.lane == lane and not h.trails:
			out = h
	return out


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var tail := start + t * speed
	for i in segments:
		var s := posmod(tail + (segments - 1 - i) * spacing, PERIMETER)
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
	for i in segments:
		if sim.bird_touches_circle(xs[i], ys[i], seg_radius):
			return true
	return false


## No exit where this crawler will be in the bird's way as it flies in.
func blocks_exit(sim: GameSim, side: int, y: int) -> bool:
	var span := _in_the_way(sim, start, side, t + sim.steps_to_exit(side), 0)
	return y > span[0] - exit_clear() and y < span[1] + exit_clear()


## The wall ahead just got its spikes. If the crawlers will cover its free
## slots when the bird gets there, spikes come off the nearest run of slots
## they leave alone, so there is always a spot to bounce on that is free of
## both. The first crawler does this for all of them. A wall with an open exit
## is left as it is (blocks_exit kept the exit clear).
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var s := sim.state
	if s.exit_open and s.exit_side == side:
		return mask
	var arrive := t + sim.steps_to_wall(side)
	var covered := 0
	var first := true
	for h in sim.room.hazards:
		if h.kind != kind:
			continue
		if first and h != self:
			return mask
		first = false
		var from: int = h.start
		var span: PackedInt32Array = h._in_the_way(sim, from, side, arrive, h.wall_window())
		var clear: int = h.slot_clear()
		for slot in SimConfig.SLOT_COUNT:
			var cy := SimConfig.slot_center_y(slot)
			if cy > span[0] - clear and cy < span[1] + clear:
				covered |= 1 << slot
	if covered == 0:
		return mask
	return mask & ~_best_run(mask, covered, s.anchor_y)


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


## The heights [lowest y, highest y] of the segments of a crawler (tail at path
## position `from` at t = 0) that are in the way of a bird reaching wall `side`
## at room step `arrive`: those it comes within near_x() of sideways in the
## wall_window() steps before, and the `after` steps after as it flies back.
## [FAR, -FAR] when none is.
func _in_the_way(sim: GameSim, from: int, side: int, arrive: int, after: int) -> PackedInt32Array:
	var r := SimConfig.BIRD_RADIUS
	var wall := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var inward := -SimConfig.SPEED_X if side == 1 else SimConfig.SPEED_X
	var lo := FAR
	var hi := -FAR
	var near := near_x()
	for d in range(-wall_window(), after + 1):
		var bird_x := wall + inward * absi(d)
		var tail := from + (arrive + d) * speed
		for i in segments:
			var s := posmod(tail + i * spacing, PERIMETER)
			if absi(path_x(s) - bird_x) < near:
				var y := path_y(s)
				lo = mini(lo, y)
				hi = maxi(hi, y)
	return PackedInt32Array([lo, hi])


func checksum(h: int) -> int:
	var out := mix_all(h, [lane, start])
	for i in segments:
		out = mix_all(out, [xs[i], ys[i]])
	if segments != SEGMENTS or speed != SPEED or reserve != 0 or trails:
		out = mix_all(out, [segments, seg_radius, spacing, speed, reserve, int(trails)])
	return out
