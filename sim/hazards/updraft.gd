extends Hazard
## A column of rising air in the middle of the room (Updraft). While the bird's
## center is inside the band, every step adds a fixed lift to its vertical
## speed. Never deadly; the ceiling still is.

const SUB := SimConfig.SUB
## Half the band width (the band is 120 px wide).
const HALF_W := 60 * SUB
## Upward speed added per step while inside: two thirds of gravity, so the bird
## floats and flaps carry it further, but it still sinks slowly. Tied to
## SimConfig.GRAVITY so a physics change can't turn it into a rocket.
const LIFT := SimConfig.GRAVITY * 2 / 3

## Band edges, sub-units.
var x0 := 0
var x1 := 0
var lift := LIFT


func _init() -> void:
	kind = "updraft"
	x0 = SimConfig.WORLD_W / 2 - HALF_W
	x1 = SimConfig.WORLD_W / 2 + HALF_W


func inside(sim: GameSim) -> bool:
	return sim.state.x >= x0 and sim.state.x <= x1


func touch(sim: GameSim) -> void:
	if inside(sim):
		var vy := sim.state.vy - lift
		sim.state.vy = clampi(vy, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)


func checksum(h: int) -> int:
	return mix_all(h, [x0, x1, lift])
