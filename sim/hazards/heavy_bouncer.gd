extends "res://sim/hazards/bouncer.gd"
## Heavy Bramble: gravity pulls it down and every floor bounce throws it up
## again, to a peak about 220 px or 340 px above the floor in turn. The top
## of the room stays clear.

const HEAVY_RADIUS := 22 * SimConfig.SUB
## 2.5 px across per step.
const HEAVY_SPEED_X := 160
const GRAVITY := 8
## Launch speeds off the floor, for peaks of 220 px and 340 px (gravity is
## added before each move, so a peak is v * v / (2 * GRAVITY) - v / 2).
const LAUNCH: Array[int] = [479, 594]

## Floor bounces so far.
var bounces := 0


func _init() -> void:
	super(HEAVY_RADIUS)


func setup(sim: GameSim, rng: SimRng) -> void:
	super.setup(sim, rng)
	vx = signi(vx) * HEAVY_SPEED_X
	vy = 0


func step(sim: GameSim) -> void:
	vy += GRAVITY
	x += vx
	y += vy
	bounce_sides(sim)
	bounce_top()
	if y > bottom_y():
		y = bottom_y()
		vy = -LAUNCH[bounces % 2]
		bounces += 1


## Its path isn't a straight bounce, so it can't say ahead where it will be.
func straight_path() -> bool:
	return false


## Its arcs don't depend on the bird: adjust_wall plays them forward.
func predictable() -> bool:
	return true


## The escort rule (Bouncer), and a way over the ball: the wall the bird flies
## to keeps a free run (the room's gap, or as much as fits) above the highest
## the ball gets while the bird crosses, so the bird is never held down in the
## ball's band. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var out := super.adjust_wall(sim, side, mask)
	var at := sim.steps_to_wall(side)
	var keep := path_save()
	var peak := y
	for k in at:
		path_step(sim)
		peak = mini(peak, y)
	path_restore(keep)
	var clear := peak - radius - SimConfig.BIRD_RADIUS - ESCORT_MARGIN
	var ok := 0
	for slot in SimConfig.SLOT_COUNT:
		if SimConfig.slot_center_y(slot) < clear:
			ok |= 1 << slot
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(all & ~ok))
	return RoomRules.keep_run(out, need, ok)


func path_step(sim: GameSim) -> void:
	step(sim)


func path_save() -> Array[int]:
	var a := super.path_save()
	a.append(bounces)
	return a


func path_restore(a: Array[int]) -> void:
	super.path_restore(a)
	bounces = a[4]


func checksum(h: int) -> int:
	return mix_all(super.checksum(h), [bounces])
