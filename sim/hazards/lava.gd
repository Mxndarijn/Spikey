extends Hazard
## Lava Rise: a deadly line that creeps up from the floor by STEP for every
## point scored in the room, up to
## MAX_RISES. A cool stone shows up once it has risen STONE_AFTER times;
## touching it sends the line back to rest. The line glides at SPEED, so it
## never jumps onto the bird.
##
## Fair: the wall ahead always keeps a free run clear of where the line will
## be (adjust_wall), and an exit never goes where the line could cover it
## before the bird gets there (blocks_exit).

const SUB := SimConfig.SUB
const STEP := 30 * SUB
## 210 px: at least 360 px of room always stays open.
const MAX_RISES := 7
## 1.25 px a step: one STEP in 24 steps.
const SPEED := 80
const STONE_RADIUS := 14 * SUB
const STONE_AFTER := 3
## The stone is at least this far from where the line is heading, and this far
## from the other edge.
const STONE_CLEAR := 90 * SUB
const STONE_EDGE := 80 * SUB
## An exit's centre stays this far from the line it could meet.
const EXIT_CLEAR := SimConfig.BIRD_RADIUS + 24 * SUB
## A free run on the wall ahead is this many slots, wholly clear of the line.
const RUN := 3

## The line's height now (the lava's top).
var line := SimConfig.KILL_BOTTOM
var rises := 0
## Room points already counted into `rises`.
var counted := 0
var stone_on := false
var stone_x := 0
var stone_y := 0


func _init() -> void:
	kind = "lava"


func setup(sim: GameSim, _rng: SimRng) -> void:
	line = rest()
	counted = sim.room.points


## The line at rest (where the plain room's kill line is).
func rest() -> int:
	return SimConfig.KILL_BOTTOM


## Where the line sits after `n` rises.
func line_at(n: int) -> int:
	return SimConfig.KILL_BOTTOM - n * STEP


## Rises once the points scored since the last count are in.
func rises_due(sim: GameSim) -> int:
	return mini(rises + sim.room.points - counted, MAX_RISES)


func step(_sim: GameSim) -> void:
	line += clampi(line_at(rises) - line, -SPEED, SPEED)


func kills(sim: GameSim) -> bool:
	var r := SimConfig.BIRD_RADIUS
	return line < SimConfig.KILL_BOTTOM and sim.state.y + r >= line


func touch(sim: GameSim) -> void:
	if stone_on and sim.bird_touches_circle(stone_x, stone_y, STONE_RADIUS):
		stone_on = false
		rises = 0


## Whether a slot's spike-free span lies wholly on the open side of `edge`.
func _slot_clear(slot: int, edge: int) -> bool:
	var cy := SimConfig.slot_center_y(slot)
	var half := SimConfig.SLOT_SIZE / 2
	return cy + half <= edge - SimConfig.BIRD_RADIUS


## Keeps a free run of RUN slots clear of where the line is heading. If the
## wall has none, the run nearest the bird is cleared. No RNG draws.
func adjust_wall(sim: GameSim, _side: int, mask: int) -> int:
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
	if first_ok < 0 or last_ok - first_ok + 1 < RUN:
		return mask
	var c0 := SimConfig.slot_center_y(0)
	var near := (sim.state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE
	var mid := clampi(near, first_ok + 1, last_ok - 1)
	for slot in range(mid - 1, mid + 2):
		mask &= ~(1 << slot)
	return mask


## Counts the new points into the line's rise and puts out a stone when it
## has risen far enough and none is out. Draws: two, only when a stone appears.
func on_bounce(sim: GameSim, rng: SimRng) -> void:
	rises = rises_due(sim)
	counted = sim.room.points
	if stone_on or rises < STONE_AFTER:
		return
	var heading := line_at(rises)
	var lo := SimConfig.KILL_TOP + STONE_EDGE
	var hi := heading - STONE_CLEAR
	stone_x = (110 + rng.next_below(141)) * SUB
	stone_y = lo + rng.next_below(maxi(hi - lo, 0) + 1)
	stone_on = true


## The exit opens one point after it is planned, so the line may rise once
## more before the bird gets there.
func blocks_exit(sim: GameSim, _side: int, y: int) -> bool:
	var worst := line_at(mini(rises_due(sim) + 1, MAX_RISES))
	return y > worst - EXIT_CLEAR


func checksum(h: int) -> int:
	return mix_all(h, [line, rises, counted, int(stone_on), stone_x, stone_y])
