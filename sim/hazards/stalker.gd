extends Hazard
## A pair of spikes on a rail (Stalker Rail). It sits on the wall the bird is
## heading to and slides toward the bird's height at a capped speed, so the
## bird can always outfly it.

## One spike of the pair: as deep and wide as a wall spike.
const DEPTH := SimConfig.SPIKE_DEPTH
const HALF_BASE := SimConfig.SPIKE_HALF_BASE
## Half the pair's height (two spikes stacked).
const HALF_H := 2 * SimConfig.SPIKE_HALF_BASE
## Fastest slide per step (1.25 px; a flap moves the bird 8 px).
const MAX_SPEED := 80
## The rail spans the wall's spike slots.
const MIN_Y := SimConfig.SLOT_TOP + HALF_H
const MAX_Y := SimConfig.SLOT_TOP + SimConfig.SLOT_COUNT * SimConfig.SLOT_SIZE - HALF_H

## 0 = left wall, 1 = right wall.
var side := 1
## Centre of the pair.
var y := 0
## The x of the wall it is on (where the spikes' bases sit).
var x := 0


func _init() -> void:
	kind = "stalker"


func setup(sim: GameSim, rng: SimRng) -> void:
	side = 1 if sim.state.vx > 0 else 0
	y = MIN_Y + rng.next_below(MAX_Y - MIN_Y + 1)
	x = base_x(sim)


func step(sim: GameSim) -> void:
	side = 1 if sim.state.vx > 0 else 0
	var target := clampi(sim.state.y, MIN_Y, MAX_Y)
	y += clampi(target - y, -MAX_SPEED, MAX_SPEED)
	x = base_x(sim)


## The x of the wall it is on.
func base_x(sim: GameSim) -> int:
	return sim.room.wall_left() if side == 0 else sim.room.wall_right()


## The way the spikes point (into the room).
func dir() -> int:
	return 1 if side == 0 else -1


func kills(sim: GameSim) -> bool:
	var bx := x
	var tip := bx + dir() * DEPTH
	var r := SimConfig.BIRD_RADIUS
	for cy: int in [y - HALF_BASE, y + HALF_BASE]:
		if SimMath.circle_hits_triangle(
			sim.state.x, sim.state.y, r, bx, cy - HALF_BASE, bx, cy + HALF_BASE, tip, cy
		):
			return true
	return false


func checksum(h: int) -> int:
	return mix_all(h, [side, y, x])
