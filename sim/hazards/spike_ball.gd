extends Hazard
## A still spiked ball (Coin Garden, Spiked Decoy): it takes the place of one
## of the four coins. Drawn in the spike colour with teeth, never like a coin.
## Touching it kills.
##
## It sits on one of the coin spots, drawn at room start; a spot that would be
## in the bird's way right after it starts or comes out of a portal is skipped.
## The room's coins come before it; the coin on its spot is taken away.

const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")

const SUB := SimConfig.SUB
## Its spike tips; all of it kills.
const RADIUS := 15 * SUB

var x := 0
var y := 0
## The spots it can take, as x, y pairs (sub-units).
var spots := PackedInt32Array()


func _init(p_spots: PackedInt32Array = PackedInt32Array()) -> void:
	kind = "spike_ball"
	spots = p_spots


func setup(sim: GameSim, rng: SimRng) -> void:
	var n := spots.size() / 2
	var first := rng.next_below(n)
	var pick := first
	for k in n:
		var i := (first + k) % n
		if not _in_the_way(sim, spots[2 * i], spots[2 * i + 1]):
			pick = i
			break
	x = spots[2 * pick]
	y = spots[2 * pick + 1]
	for h in sim.room.hazards:
		var c := h as CoinPickup
		if c != null and c.x == x and c.y == y:
			c.alive = false


## Whether a ball at (bx, by) is on the bird's first, forced hop, in its start
## lane, or on the path a bird out of a portal flies while it reads the room.
func _in_the_way(sim: GameSim, bx: int, by: int) -> bool:
	var margin := 10 * SUB
	if FairLanes.start_path_hits_rect(
		sim, bx - RADIUS, by - RADIUS, bx + RADIUS, by + RADIUS, margin
	):
		return true
	if FairLanes.blocks_start_lane(sim, bx - RADIUS, by - RADIUS, bx + RADIUS, by + RADIUS):
		return true
	if not sim.state.started:
		return false
	var path := FairLanes.arrival_path(sim)
	for k in FairLanes.ARRIVAL_PATH_TICKS:
		if FairLanes.arrival_path_hits(path, k, bx, by, RADIUS):
			return true
	return false


func kills(sim: GameSim) -> bool:
	return sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	return mix_all(h, [x, y])
