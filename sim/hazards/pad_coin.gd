extends "res://sim/hazards/coin_pickup.gd"
## Bumper Court, Goal Pad: a coin riding just above one of the edge pads. Land
## on that pad (or fly up into the ceiling pad) to take it; a second later the
## next one shows up on the other pad. Kind "coin". The room's pads must come
## before it in the room's hazards.

const EdgePad := preload("res://sim/hazards/edge_pad.gd")

## Steps after it is taken before the next coin shows up.
const RESPAWN := 60

## True: on the ceiling pad, false: on the floor pad.
var on_top := false
## Steps until it shows up again (0 = out).
var wait := 0


func _init(p_on_top: bool = false) -> void:
	super(0, 0, 0)
	on_top = p_on_top


func setup(sim: GameSim, _rng: SimRng) -> void:
	_follow(sim)


func visible() -> bool:
	return wait == 0


func step(sim: GameSim) -> void:
	if wait > 0:
		wait -= 1
	_follow(sim)


## Rides the middle of its pad (kept in the coin band at the pad's far ends),
## at the edge of the coin band, so the bird flies through it on the way onto
## the pad.
func _follow(sim: GameSim) -> void:
	for h in sim.room.hazards:
		var pad := h as EdgePad
		if pad != null and pad.top == on_top:
			x = clampi((pad.x0() + pad.x1()) / 2, SimConfig.COIN_MIN_X, SimConfig.COIN_MAX_X)
			y = SimConfig.COIN_MIN_Y if on_top else SimConfig.COIN_MAX_Y
			return


func touch(sim: GameSim) -> void:
	if visible() and sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS):
		sim.collect_coin(x, y)
		on_top = not on_top
		wait = RESPAWN
		_follow(sim)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, int(on_top), wait])
