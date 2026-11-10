extends "res://sim/hazards/bouncer.gd"
## Rev-Up Bramble: starts at 60% of the usual speed and gets 10% faster with
## every bounce off an edge, up to 130%. At the top it still crosses the room
## a little slower than the bird does.

const MAX_LEVEL := 7

## Bounces counted so far, 0..MAX_LEVEL. Speed is (6 + level) tenths.
var level := 0


func setup(sim: GameSim, rng: SimRng) -> void:
	super.setup(sim, rng)
	level = 0
	_set_speed()


func step(sim: GameSim) -> void:
	if move(sim) and level < MAX_LEVEL:
		level += 1
		_set_speed()


func _set_speed() -> void:
	vx = signi(vx) * SPEED_X * (6 + level) / 10
	vy = signi(vy) * SPEED_Y * (6 + level) / 10


func checksum(h: int) -> int:
	return mix_all(super.checksum(h), [level])
