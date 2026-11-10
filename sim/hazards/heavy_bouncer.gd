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


func checksum(h: int) -> int:
	return mix_all(super.checksum(h), [bounces])
