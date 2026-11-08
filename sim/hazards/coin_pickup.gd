extends Hazard
## A coin placed by the room (Coin Garden, Egg Hunt, Countdown, Slow-Mo). Fly
## through it to collect it. It can wait to appear (`appear_at`) and fall.

var x := 0
var y := 0
## Step at which it appears (Countdown lights one up every second).
var appear_at := 0
## Falling speed per step (Orchard Drop); it disappears below the floor.
var vy := 0


func _init(p_x: int = 0, p_y: int = 0, p_appear_at: int = 0) -> void:
	kind = "coin"
	x = p_x
	y = p_y
	appear_at = p_appear_at


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
