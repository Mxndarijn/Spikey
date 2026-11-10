extends "res://sim/hazards/coin_pickup.gd"
## A coin circling a point (Coin Garden, Orbiting Coins): the four coins of the
## diamond turn slowly around the middle of the room. Kind "coin", so it draws
## and pays like any room coin.

## Steps for one full turn (about ten seconds).
const PERIOD := 640

## The point it circles and how far out, sub-units.
var cx := 0
var cy := 0
var radius := 0
## Where on the circle it starts (SimTrig angle, 1024 = a full turn).
var phase := 0


func _init(p_cx: int = 0, p_cy: int = 0, p_radius: int = 0, p_phase: int = 0) -> void:
	super(p_cx, p_cy, 0)
	cx = p_cx
	cy = p_cy
	radius = p_radius
	phase = p_phase
	_place()


func setup(_sim: GameSim, _rng: SimRng) -> void:
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var a := phase + t * SimTrig.TURN / PERIOD
	x = cx + radius * SimTrig.cos_t(a) / SimTrig.ONE
	y = cy + radius * SimTrig.sin_t(a) / SimTrig.ONE


func checksum(h: int) -> int:
	return mix_all(h, [x, y, cx, cy, radius, phase])
