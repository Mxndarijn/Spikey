extends Hazard
## Buttons: two hanging buttons. The top one hangs from the ceiling on a rod
## and is pressed from below, the bottom one stands on a post from the floor
## and is pressed by landing on it. Press the lit one (the top first), then
## the other, in turn: only a press of the lit button scores, wall bounces
## score nothing here (RoomDef.bounce_points). Ten presses open the exit, at
## the next wall bounce as in every room.
##
## A button's face sits GAP inside the kill line (the ceiling and floor keep
## their spikes, also behind a button). GAP is one hop plus a little: a bird
## that taps just under the top face and misses the button stops below the
## ceiling spikes. A press never sends the bird at an edge: the top one pushes
## it down, the bottom one throws it up. The bird touching a button from the
## side (between the button and the edge) is put back on the room side of the
## face, and that is no press. The rods are only looks.
##
## Where each button sits across the cage is drawn from the room's RNG at
## room start (top first, then bottom), on an 8 px grid, at least MARGIN from
## the walls, and never changes in the room. Variants (the room's variant id):
##   classic: WIDE buttons.
##   slim:    SLIM buttons.
##   apart:   SLIM buttons, the bottom one in the other half of the room,
##            centres at least APART_MIN apart, so you cross over too.

const SUB := SimConfig.SUB
const WIDE := 120 * SUB
const SLIM := 96 * SUB
const GRID := 8 * SUB
## A button's ends are never nearer a wall than this: past the wall spike
## tips (SPIKE_DEPTH) by more than a bird's width.
const MARGIN := 64 * SUB
const APART_MIN := 96 * SUB
## From the kill line to a button's face: one flap's hop plus a margin. A
## flap rises 59 px in steps (sum of FLAP_VY + k GRAVITY while going up), so
## a bird that taps as its top meets the face height and misses the button
## stops 5 px short of the ceiling's kill line. The same on the floor side.
const GAP := 64 * SUB
## How deep a button is, face to back (the cap and its base).
const BODY := 26 * SUB
const TOP_FACE := SimConfig.KILL_TOP + GAP
const BOTTOM_FACE := SimConfig.KILL_BOTTOM - GAP
## The bird counts as on a button if its centre is this close past an end.
const GRACE := SimConfig.BIRD_RADIUS / 2
## Speeds the bird leaves the buttons with: the top one pushes down gently,
## the bottom one throws a little harder than a flap.
const TOP_VY := -SimConfig.FLAP_VY * 3 / 5
const BOTTOM_VY := SimConfig.FLAP_VY * 6 / 5

var width := WIDE
## Left ends of the two buttons, sub-units.
var top_x0 := 0
var bottom_x0 := 0
## The button that scores next: true = the top one.
var lit_top := true
## Correct presses in this room.
var presses := 0
## Steps since the last correct press, and since the last press of the button
## that wasn't lit (for the painter).
var since_press := 1000
var since_wrong := 1000
## Which button was pressed last (for the painter): true = the top one.
var last_top := true


func _init() -> void:
	kind = "button_pair"


func setup(sim: GameSim, rng: SimRng) -> void:
	var apart := false
	match sim.room.variant_id():
		"slim":
			width = SLIM
		"apart":
			width = SLIM
			apart = true
		_:
			width = WIDE
	var lo := MARGIN
	var hi := SimConfig.WORLD_W - MARGIN - width
	var mid := SimConfig.WORLD_W / 2
	if apart:
		# The top one in an outer band of either half, so a bottom spot
		# APART_MIN away in the other half always exists.
		var left_hi := mid - APART_MIN / 2 - width / 2
		var right_lo := _snap(mid + APART_MIN / 2 - width / 2)
		var n_left := _spots(lo, left_hi)
		var k := rng.next_below(n_left + _spots(right_lo, hi))
		top_x0 = lo + GRID * k if k < n_left else right_lo + GRID * (k - n_left)
	else:
		top_x0 = lo + GRID * rng.next_below(_spots(lo, hi))
	if apart:
		# Centres at least APART_MIN apart, in the other half of the room.
		var top_c := top_x0 + width / 2
		if top_c < mid:
			lo = maxi(lo, maxi(mid, top_c + APART_MIN) - width / 2)
		else:
			hi = mini(hi, mini(mid, top_c - APART_MIN) - width / 2)
		lo = _snap(lo)
	bottom_x0 = lo + GRID * rng.next_below(_spots(lo, hi))


## Spots on the grid from `lo` to `hi` (at least one).
static func _spots(lo: int, hi: int) -> int:
	return maxi((hi - lo) / GRID + 1, 1)


## The first grid spot (from MARGIN, every GRID) at or past `x`.
static func _snap(x: int) -> int:
	if x <= MARGIN:
		return MARGIN
	return MARGIN + (x - MARGIN + GRID - 1) / GRID * GRID


func step(_sim: GameSim) -> void:
	since_press += 1
	since_wrong += 1


func x0(top: bool) -> int:
	return top_x0 if top else bottom_x0


func x1(top: bool) -> int:
	return x0(top) + width


func covers(top: bool, x: int) -> bool:
	return x >= x0(top) - GRACE and x <= x1(top) + GRACE


## The y of button `top`'s face, the side the bird presses.
static func face(top: bool) -> int:
	return TOP_FACE if top else BOTTOM_FACE


func touch(sim: GameSim) -> void:
	for top: bool in [true, false]:
		_touch(sim, top)


func _touch(sim: GameSim, top: bool) -> void:
	if not covers(top, sim.state.x):
		return
	var r := SimConfig.BIRD_RADIUS
	var y := sim.state.y
	var f := face(top)
	if top and (y - r > f or y + r < f - BODY):
		return
	if not top and (y + r < f or y - r > f + BODY):
		return
	# On the room side of the face: a press. Else it came in from the side.
	var pressed := y > f if top else y < f
	if top:
		sim.state.y = f + r + 1
		sim.state.vy = TOP_VY
	else:
		sim.state.y = f - r - 1
		sim.state.vy = BOTTOM_VY
	last_top = top
	if pressed and top == lit_top and sim._score_press():
		lit_top = not lit_top
		presses += 1
		since_press = 0
	else:
		since_wrong = 0


func checksum(h: int) -> int:
	return mix_all(
		h,
		[width, top_x0, bottom_x0, int(lit_top), presses, since_press, since_wrong, int(last_top)]
	)
