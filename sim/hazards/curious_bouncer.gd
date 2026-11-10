extends "res://sim/hazards/bouncer.gd"
## Curious Bramble: crosses like the usual ball, but steers up or down toward
## the bird's height. It turns slowly and its top climb (2.4 px a step) is
## half a flap's, so the bird can always get away.

## Change of vy per step, at most.
const STEER := 4
const MAX_VY := 154
const START_VY := 38
## Height difference per sub-unit of steer.
const STEER_DIV := 512

## Which way it is looking: -1 up, 1 down, 0 level with the bird (painter).
var look := 0


func setup(sim: GameSim, rng: SimRng) -> void:
	super.setup(sim, rng)
	vy = signi(vy) * START_VY


func step(sim: GameSim) -> void:
	var d := sim.state.y - y
	look = signi(d)
	vy = clampi(vy + clampi(d / STEER_DIV, -STEER, STEER), -MAX_VY, MAX_VY)
	move(sim)


## Its path isn't a straight bounce, so it can't say ahead where it will be.
func straight_path() -> bool:
	return false


func checksum(h: int) -> int:
	return mix_all(super.checksum(h), [look])
