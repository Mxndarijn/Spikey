extends Hazard
## A coin placed by the room (Coin Garden, Egg Hunt, Countdown, Slow-Mo). Fly
## through it to collect it. It can wait to appear (`appear_at`) and fall.

const Block := preload("res://sim/hazards/block.gd")
## Egg Hunt: gap between an egg and its island, and the furthest right an egg
## goes (else it sits on the island's left).
const BESIDE_GAP := 22 * SimConfig.SUB
const BESIDE_MAX_X := 290 * SimConfig.SUB

var x := 0
var y := 0
## Step at which it appears (Countdown lights one up every second).
var appear_at := 0
## Falling speed per step (Orchard Drop); it disappears below the floor.
var vy := 0
## Egg Hunt: sits beside the Floating Isles island of this band (-1 = at x, y).
## The island must come before it in the room's hazards.
var beside_band := -1


func _init(p_x: int = 0, p_y: int = 0, p_appear_at: int = 0) -> void:
	kind = "coin"
	x = p_x
	y = p_y
	appear_at = p_appear_at


func setup(sim: GameSim, _rng: SimRng) -> void:
	if beside_band < 0:
		return
	for h in sim.room.hazards:
		var island := h as Block
		if island != null and island.band == beside_band:
			x = (
				island.x1 + BESIDE_GAP
				if island.x1 + BESIDE_GAP <= BESIDE_MAX_X
				else island.x0 - BESIDE_GAP
			)
			y = (island.y0 + island.y1) / 2
			return


func visible() -> bool:
	return t >= appear_at


func step(_sim: GameSim) -> void:
	if vy != 0 and visible():
		y += vy
		if y > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS:
			alive = false


func touch(sim: GameSim) -> void:
	if visible() and sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS):
		alive = false
		sim.collect_coin(x, y)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, appear_at, vy])
