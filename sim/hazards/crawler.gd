extends Hazard
## A caterpillar (Caterpillar Crawl; Summer Crab Walk is the same with a skin):
## a chain of round segments walking clockwise round a rectangle inside the
## cage (ceiling, wall, floor, wall). Every segment kills.

const SEGMENTS := 6
const SEG_RADIUS := 10 * SimConfig.SUB
## Distance along the path between segment centres.
const SPACING := 22 * SimConfig.SUB
## Path speed per step.
const SPEED := SimConfig.SUB
## The path rectangle: past the wall spikes, clear of the ceiling and floor.
const LEFT := 60 * SimConfig.SUB
const RIGHT := 300 * SimConfig.SUB
const TOP := 80 * SimConfig.SUB
const BOTTOM := 560 * SimConfig.SUB
const W := RIGHT - LEFT
const H := BOTTOM - TOP
const PERIMETER := 2 * (W + H)
## A crawler starts with its whole body on the ceiling or floor edge, its head
## at least 50 px from the next corner, so it never comes down a wall onto the
## bird right at the start of the room.
const START_SPAN := W - (SEGMENTS - 1) * SPACING - 50 * SimConfig.SUB

## 0 starts on the ceiling heading right, 1 on the floor heading left.
var lane := 0
## Path position of the tail at t = 0.
var start := 0
## Segment centres, head first (filled every step for the painter).
var xs: Array[int] = []
var ys: Array[int] = []


func _init(p_lane: int = 0) -> void:
	kind = "crawler"
	lane = p_lane


func setup(_sim: GameSim, rng: SimRng) -> void:
	start = rng.next_below(START_SPAN) + lane * (W + H)
	xs.resize(SEGMENTS)
	ys.resize(SEGMENTS)
	_place()


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var tail := start + t * SPEED
	for i in SEGMENTS:
		var s := posmod(tail + (SEGMENTS - 1 - i) * SPACING, PERIMETER)
		if s < W:
			xs[i] = LEFT + s
			ys[i] = TOP
		elif s < W + H:
			xs[i] = RIGHT
			ys[i] = TOP + s - W
		elif s < 2 * W + H:
			xs[i] = RIGHT - (s - W - H)
			ys[i] = BOTTOM
		else:
			xs[i] = LEFT
			ys[i] = BOTTOM - (s - 2 * W - H)


func kills(sim: GameSim) -> bool:
	for i in SEGMENTS:
		if sim.bird_touches_circle(xs[i], ys[i], SEG_RADIUS):
			return true
	return false


func checksum(h: int) -> int:
	var out := mix_all(h, [lane, start])
	for i in SEGMENTS:
		out = mix_all(out, [xs[i], ys[i]])
	return out
