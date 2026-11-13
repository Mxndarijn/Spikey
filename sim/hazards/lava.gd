extends Hazard
## Lava Rise: a deadly line that creeps up from the floor by STEP for every
## point scored in the room (rafts: RAFT_PER_POINT steps a point), with no cap:
## left alone it fills the room (FULL_RISES). The point that shows the room's
## exit (its ghost, a bounce early) and those after it bring no rise: the
## player sees where the exit is and has that bounce to sink the lava under
## it. The line rises at SPEED, so it never jumps onto the bird, and sinks at
## SINK_SPEED, so a sink clears the way at once. Keeping it low is the player's job: lava
## over an exit blocks it. What pushes it back depends on the variant:
## - lava: a cool stone shows up once it has risen STONE_AFTER times; touching
##   it sends the line back to rest.
## - cold (Cold Wall): instead of the stone, a block of ice sits in one wall
##   slot (that slot and its neighbours never get spikes). Bouncing off the wall
##   on the ice sends the line back to rest.
## - rafts: no stone, and the lava rises twice as fast. Every RAFT_EVERY
##   points a raft of cooled rock floats up (at most MAX_RAFTS, RAFT_RISE steps
##   to come up) and drifts on the lava. Over a raft the lava is safe;
##   touching it throws the bird up like a floor pad and sinks the line
##   RAFT_SINK steps (more than it rises between two rafts). Where each raft
##   comes up is drawn at room start (RAFT_PLAN spots), and two rafts keep
##   RAFT_GAP apart, when one comes up and as they drift.
##
## Fair: the wall ahead always keeps a free run clear of where the line will
## be (adjust_wall). Exits stay where the seed puts them, also under the lava:
## a player who uses the stone, ice or rafts keeps them clear.

## Variants (the room's variant id picks one).
enum Mode { STONE, COLD, RAFTS }

const SUB := SimConfig.SUB
const STEP := 30 * SUB
## Rafts: RAFT_PER_POINT rises a point.
const RAFT_PER_POINT := 2
## Rises that bring the line over the ceiling's kill line: the room is full,
## more would change nothing (the count stops there, so a sink acts at once).
const FULL_RISES := (SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP + STEP - 1) / STEP
## 1.25 px a step: one STEP in 24 steps. Sinking is four times as fast (5 px).
const SPEED := 80
const SINK_SPEED := 4 * SPEED
const STONE_RADIUS := 14 * SUB
const STONE_AFTER := 3
## The stone is at least this far from where the line is heading, and this far
## from the other edge.
const STONE_CLEAR := 90 * SUB
const STONE_EDGE := 80 * SUB
## A free run on the wall ahead is this many slots, wholly clear of the line.
const RUN := 3
## Cold Wall: the ice block reaches this far in from the wall, over its slot.
const ICE_DEPTH := 12 * SUB
## Its slot's centre is at least this far from the bird's height when it
## appears, so it never comes up on the bird.
const ICE_AWAY := 80 * SUB
## Rafts: half its width, its height above the line, its drift speed (half a
## pixel a step) and the room it keeps from each wall.
const RAFT_HALF := 32 * SUB
const RAFT_HIGH := 8 * SUB
const RAFT_SPEED := 32
const RAFT_X_MIN := 70 * SUB + RAFT_HALF
const RAFT_X_MAX := SimConfig.WORLD_W - 70 * SUB - RAFT_HALF
## A raft comes every RAFT_EVERY points once the line has risen RAFT_FROM
## times; two can be out from RAFT_TWO rises. It floats up for RAFT_RISE steps
## (1 s) before it guards or bounces.
const RAFT_EVERY := 2
const RAFT_FROM := 2
const RAFT_TWO := 5
const MAX_RAFTS := 2
const RAFT_RISE := 60
## A raft sinks what the lava rises in one point more than the RAFT_EVERY
## points between rafts, so a player who takes every raft keeps the lava down
## and one who missed one can win it back.
const RAFT_SINK := RAFT_PER_POINT * (RAFT_EVERY + 1)
## A raft throws the bird up a little harder than a flap.
const RAFT_VY := SimConfig.FLAP_VY * 6 / 5
## Room between two rafts' edges, and so the least distance between centres.
const RAFT_GAP := 12 * SUB
const RAFT_APART := 2 * RAFT_HALF + RAFT_GAP
## Spots drawn at room start: the raft due at room point p comes up at spot
## (p / RAFT_EVERY) % RAFT_PLAN, drifting the drawn way.
const RAFT_PLAN := 6

var mode := Mode.STONE
## The line's height now (the lava's top).
var line := SimConfig.KILL_BOTTOM
var rises := 0
## Room points already counted into `rises`.
var counted := 0
var stone_on := false
var stone_x := 0
var stone_y := 0
## Cold Wall: the ice block's wall (0 left, 1 right) and slot.
var ice_on := false
var ice_side := 0
var ice_slot := 0
## Rafts: per raft whether it is out, its centre x, drift direction (+1 / -1)
## and steps since it appeared.
var raft_on: Array[bool] = [false, false]
var raft_x: Array[int] = [0, 0]
var raft_dir: Array[int] = [1, 1]
var raft_age: Array[int] = [0, 0]
## Room points when the last raft appeared.
var raft_points := 0
## The spots (centre x, way) drawn at room start.
var plan_x: Array[int] = []
var plan_dir: Array[int] = []


func _init() -> void:
	kind = "lava"


## Rafts draw their RAFT_PLAN spots here (two draws each), nothing later.
func setup(sim: GameSim, rng: SimRng) -> void:
	match sim.room.variant_id():
		"cold":
			mode = Mode.COLD
		"rafts":
			mode = Mode.RAFTS
		_:
			mode = Mode.STONE
	line = rest()
	counted = sim.room.points
	raft_points = sim.room.points
	if mode == Mode.RAFTS:
		draw_plan(rng)


## The rafts' RAFT_PLAN spots: centre x, then way, two draws each.
func draw_plan(rng: SimRng) -> void:
	plan_x.clear()
	plan_dir.clear()
	for k in RAFT_PLAN:
		plan_x.append(RAFT_X_MIN + rng.next_below(RAFT_X_MAX - RAFT_X_MIN + 1))
		plan_dir.append(1 if rng.next_below(2) == 0 else -1)


## The line at rest (where the plain room's kill line is).
func rest() -> int:
	return SimConfig.KILL_BOTTOM


## Where the line sits after `n` rises.
func line_at(n: int) -> int:
	return SimConfig.KILL_BOTTOM - n * STEP


## Rises a point brings: one, or RAFT_PER_POINT for rafts.
func per_point() -> int:
	return RAFT_PER_POINT if mode == Mode.RAFTS else 1


## Rises once the points scored since the last count are in (up to
## FULL_RISES). The point that shows the exit (one to go) and later ones bring
## none.
func rises_due(sim: GameSim) -> int:
	if sim.state.exit_open or sim.state.exit_preview or sim.points_to_exit() <= 1:
		return rises
	return mini(rises + per_point() * (sim.room.points - counted), FULL_RISES)


func step(_sim: GameSim) -> void:
	line += clampi(line_at(rises) - line, -SPEED, SINK_SPEED)
	for i in MAX_RAFTS:
		if not raft_on[i]:
			continue
		raft_age[i] += 1
		raft_x[i] += raft_dir[i] * RAFT_SPEED
		if raft_x[i] <= RAFT_X_MIN or raft_x[i] >= RAFT_X_MAX:
			raft_x[i] = clampi(raft_x[i], RAFT_X_MIN, RAFT_X_MAX)
			raft_dir[i] = -raft_dir[i]
	# Two rafts drifting at each other turn back RAFT_APART apart.
	if raft_on[0] and raft_on[1]:
		var d := raft_x[1] - raft_x[0]
		if absi(d) <= RAFT_APART and (raft_dir[1] - raft_dir[0]) * signi(d) < 0:
			raft_dir[0] = -raft_dir[0]
			raft_dir[1] = -raft_dir[1]


func kills(sim: GameSim) -> bool:
	var r := SimConfig.BIRD_RADIUS
	if line >= SimConfig.KILL_BOTTOM or sim.state.y + r < line:
		return false
	return _raft_under(sim) < 0


## A raft that is up with the bird's centre over it, or -1.
func _raft_under(sim: GameSim) -> int:
	for i in MAX_RAFTS:
		if raft_on[i] and raft_age[i] >= RAFT_RISE:
			if absi(sim.state.x - raft_x[i]) <= RAFT_HALF:
				return i
	return -1


func touch(sim: GameSim) -> void:
	if stone_on and sim.bird_touches_circle(stone_x, stone_y, STONE_RADIUS):
		stone_on = false
		rises = 0
	if ice_on and sim.bird_touches_rect(ice_x0(sim), ice_y0(), ice_x1(sim), ice_y1()):
		ice_on = false
		rises = 0
	var r := SimConfig.BIRD_RADIUS
	for i in MAX_RAFTS:
		if not raft_on[i] or raft_age[i] < RAFT_RISE:
			continue
		var x0 := raft_x[i] - RAFT_HALF
		var x1 := raft_x[i] + RAFT_HALF
		var top := line - RAFT_HIGH
		var over := _raft_under(sim) == i and sim.state.y + r >= top
		if over or sim.bird_touches_rect(x0, top, x1, line):
			raft_on[i] = false
			rises = maxi(rises - RAFT_SINK, 0)
			sim.state.y = mini(sim.state.y, top - r - 1)
			sim.state.vy = RAFT_VY
			return


## The ice block's box: over its slot, reaching ICE_DEPTH in from its wall.
func ice_x0(sim: GameSim) -> int:
	return sim.room.wall_left() if ice_side == 0 else sim.room.wall_right() - ICE_DEPTH


func ice_x1(sim: GameSim) -> int:
	return sim.room.wall_left() + ICE_DEPTH if ice_side == 0 else sim.room.wall_right()


func ice_y0() -> int:
	return SimConfig.slot_center_y(ice_slot) - SimConfig.SLOT_SIZE / 2


func ice_y1() -> int:
	return SimConfig.slot_center_y(ice_slot) + SimConfig.SLOT_SIZE / 2


## Whether a slot's spike-free span lies wholly on the open side of `edge`.
func _slot_clear(slot: int, edge: int) -> bool:
	var cy := SimConfig.slot_center_y(slot)
	var half := SimConfig.SLOT_SIZE / 2
	return cy + half <= edge - SimConfig.BIRD_RADIUS


## Keeps a free run of RUN slots clear of where the line is heading. If the
## wall has none, the run nearest the bird is cleared, and if fewer than RUN
## slots are clear of the line (rafts, lava high), all of those. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	if ice_on and side == ice_side:
		_lift_ice(sim)
		for slot in range(maxi(ice_slot - 1, 0), mini(ice_slot + 2, SimConfig.SLOT_COUNT)):
			mask &= ~(1 << slot)
	if mask == 0:
		return mask
	var edge := line_at(rises_due(sim))
	var run := 0
	var first_ok := -1
	var last_ok := -1
	for slot in SimConfig.SLOT_COUNT:
		if not _slot_clear(slot, edge):
			run = 0
			continue
		if first_ok < 0:
			first_ok = slot
		last_ok = slot
		run = 0 if RoomRules.has_slot(mask, slot) else run + 1
		if run >= RUN:
			return mask
	if first_ok < 0:
		return mask
	if last_ok - first_ok + 1 < RUN:
		for slot in range(first_ok, last_ok + 1):
			mask &= ~(1 << slot)
		return mask
	var c0 := SimConfig.slot_center_y(0)
	var near := (sim.state.anchor_y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE
	var mid := clampi(near, first_ok + 1, last_ok - 1)
	for slot in range(mid - 1, mid + 2):
		mask &= ~(1 << slot)
	return mask


## The ice block never drowns: when its wall gets new spikes and the line is
## heading within STONE_CLEAR of its slot, it moves up the wall to the lowest
## slot clear of that (not above STONE_EDGE under the ceiling). No draws.
func _lift_ice(sim: GameSim) -> void:
	var hi := line_at(rises_due(sim)) - STONE_CLEAR
	var lo := SimConfig.KILL_TOP + STONE_EDGE
	while (
		ice_slot > 0
		and SimConfig.slot_center_y(ice_slot) > hi
		and SimConfig.slot_center_y(ice_slot - 1) >= lo
	):
		ice_slot -= 1


## The stone never drowns: it floats up to stay STONE_CLEAR above where the
## line is heading (not above STONE_EDGE under the ceiling). No draws.
func _lift_stone() -> void:
	var lo := SimConfig.KILL_TOP + STONE_EDGE
	stone_y = maxi(mini(stone_y, line_at(rises) - STONE_CLEAR), lo)


## Counts the new points into the line's rise and puts out what sinks it:
## a stone (two draws), ice (one draw) or a raft (no draws: its spot was drawn
## at room start), only when one appears.
func on_bounce(sim: GameSim, rng: SimRng) -> void:
	rises = rises_due(sim)
	counted = sim.room.points
	if mode == Mode.COLD:
		_place_ice(sim, rng)
		return
	if mode == Mode.RAFTS:
		_place_raft(sim)
		return
	if stone_on:
		_lift_stone()
		return
	if rises < STONE_AFTER:
		return
	var heading := line_at(rises)
	var lo := SimConfig.KILL_TOP + STONE_EDGE
	var hi := heading - STONE_CLEAR
	stone_x = (110 + rng.next_below(141)) * SUB
	stone_y = lo + rng.next_below(maxi(hi - lo, 0) + 1)
	stone_on = true


## Puts ice on the wall the bird just left (its next spikes come after this,
## so adjust_wall keeps the ice's slots clear): in a slot STONE_CLEAR or more
## above where the line is heading, STONE_EDGE or more below the ceiling and
## ICE_AWAY or more from the anchor (never the bird's own height, so every
## player of a seed gets the same ice). One draw, only when it appears.
func _place_ice(sim: GameSim, rng: SimRng) -> void:
	if ice_on or rises < STONE_AFTER:
		return
	var heading := line_at(rises)
	var lo := SimConfig.KILL_TOP + STONE_EDGE
	var hi := heading - STONE_CLEAR
	var count := 0
	for slot in SimConfig.SLOT_COUNT:
		if _ice_fits(sim, slot, lo, hi):
			count += 1
	if count == 0:
		return
	var pick := rng.next_below(count)
	for slot in SimConfig.SLOT_COUNT:
		if not _ice_fits(sim, slot, lo, hi):
			continue
		if pick == 0:
			ice_slot = slot
			break
		pick -= 1
	ice_side = 0 if sim.state.vx > 0 else 1
	ice_on = true


func _ice_fits(sim: GameSim, slot: int, lo: int, hi: int) -> bool:
	var cy := SimConfig.slot_center_y(slot)
	return cy >= lo and cy <= hi and absi(cy - sim.state.anchor_y) >= ICE_AWAY


## Floats a raft up every RAFT_EVERY points once the line has risen
## RAFT_FROM times, while fewer than allowed are out, at the room point's
## planned spot. Next to a raft that is out it moves to RAFT_APART from it,
## on the side the spot is on if there is room there, and drifts away from it.
## No draws.
func _place_raft(sim: GameSim) -> void:
	if rises < RAFT_FROM or sim.room.points - raft_points < RAFT_EVERY:
		return
	var allowed := MAX_RAFTS if rises >= RAFT_TWO else 1
	var out := 0
	var free := -1
	for i in MAX_RAFTS:
		if raft_on[i]:
			out += 1
		elif free < 0:
			free = i
	if out >= allowed or free < 0:
		return
	var k := (sim.room.points / RAFT_EVERY) % RAFT_PLAN
	var x: int = plan_x[k]
	var way: int = plan_dir[k]
	var other := 1 - free
	if raft_on[other] and absi(x - raft_x[other]) < RAFT_APART:
		var o := raft_x[other]
		var side := 1 if x >= o else -1
		if o + side * RAFT_APART < RAFT_X_MIN or o + side * RAFT_APART > RAFT_X_MAX:
			side = -side
		x = o + side * RAFT_APART
		way = side
	raft_x[free] = x
	raft_dir[free] = way
	raft_age[free] = 0
	raft_on[free] = true
	raft_points = sim.room.points


func checksum(h: int) -> int:
	var out := mix_all(h, [mode, line, rises, counted, int(stone_on), stone_x, stone_y])
	if mode == Mode.COLD:
		out = mix_all(out, [int(ice_on), ice_side, ice_slot])
	elif mode == Mode.RAFTS:
		out = mix_all(out, [raft_points])
		for i in MAX_RAFTS:
			out = mix_all(out, [int(raft_on[i]), raft_x[i], raft_dir[i], raft_age[i]])
	return out
