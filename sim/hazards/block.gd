extends Hazard
## A still box in the room (Floating Isles). With `fade_period` set it fades in
## and out on a cycle and is only deadly while solid (Ghost Doors).

## Floating Isles bands (see `band`).
const BAND := 110 * SimConfig.SUB
const BAND_TOP := 96 * SimConfig.SUB
## Islands stay this far from the side walls.
const SIDE := 80 * SimConfig.SUB
## Room kept between an island and the bird's first hop.
const START_MARGIN := 6 * SimConfig.SUB
## Least clear height between islands in neighbouring bands that overlap side
## to side: room to hover in (one hop is about 60 px plus the bird).
const MIN_GAP := 95 * SimConfig.SUB
## Islands in neighbouring bands closer than this side to side count as
## overlapping: the slot between their ends is too short to change height in.
const PINCH_X := 48 * SimConfig.SUB
## The arrival lane, kept clear in front of a bird that comes out of a wall
## (portal or revive): this far into the room, and from ARRIVAL_UP above the
## bird (one hop) to ARRIVAL_DOWN below it.
const ARRIVAL_W := 150 * SimConfig.SUB
const ARRIVAL_UP := 75 * SimConfig.SUB
const ARRIVAL_DOWN := 45 * SimConfig.SUB
## An island this close to a wall is in front of an exit there when it is
## level with the exit's middle, give or take the bird and a margin. Planning
## an exit past the islands uses EXIT_MARGIN: small enough that one island
## rules out two slots at most, so the four of them never rule out a whole
## wall. Placing islands around an exit that is already there (revive) uses
## EXIT_ROOM, a whole slot.
const EXIT_CLEAR_X := 130 * SimConfig.SUB
const EXIT_MARGIN := 8 * SimConfig.SUB
const EXIT_ROOM := SimConfig.SLOT_SIZE

## Box corners, sub-units.
var x0 := 0
var y0 := 0
var x1 := 0
var y1 := 0
## Fading: 0 = always solid. Otherwise solid for the first `solid_ticks` of
## every `fade_period` steps, offset by `phase`.
var fade_period := 0
var solid_ticks := 0
var phase := 0
## Floating Isles: which band of the room the island sits in (-1 = fixed box).
## Each band is BAND tall and an island fills at most 36 px of it, so the bird
## can always fly around every island.
var band := -1


func _init(p_x0: int = 0, p_y0: int = 0, p_x1: int = 0, p_y1: int = 0) -> void:
	kind = "block"
	x0 = p_x0
	y0 = p_y0
	x1 = p_x1
	y1 = p_y1


func setup(sim: GameSim, rng: SimRng) -> void:
	if band < 0:
		return
	var sub := SimConfig.SUB
	var w := (50 + rng.next_below(41)) * sub
	var h := (24 + rng.next_below(13)) * sub
	x0 = SIDE + rng.next_below(200 * sub - w)
	y0 = BAND_TOP + band * BAND + 10 * sub + rng.next_below(BAND - h - 20 * sub)
	# The drawn spot first; if it is in the way, the same band a little lower
	# (just clear of the island above), at its top or bottom; then beside the
	# island above, at the far end, the near end and the middle. No extra
	# draws, so the seed still decides everything.
	var band_top := BAND_TOP + band * BAND + 10 * sub
	var band_bottom := BAND_TOP + (band + 1) * BAND - 10 * sub - h
	var far_x := SimConfig.WORLD_W - SIDE - w
	var mid_x := (SimConfig.WORLD_W - w) / 2
	var clear_y := band_top
	var right_x := far_x
	var left_x := SIDE
	var above := _neighbour(sim)
	if not above.is_empty():
		clear_y = above[2] + MIN_GAP
		right_x = above[1] + PINCH_X
		left_x = above[0] - PINCH_X - w
	clear_y = clampi(maxi(clear_y, y0), band_top, band_bottom)
	right_x = clampi(right_x, SIDE, far_x)
	left_x = clampi(left_x, SIDE, far_x)
	var found := false
	for cx: int in [x0, right_x, left_x, far_x, SIDE, mid_x]:
		for cy: int in [y0, clear_y, band_top, band_bottom]:
			if _in_the_way(sim, cx, cy, cx + w, cy + h):
				continue
			x0 = cx
			y0 = cy
			found = true
			break
		if found:
			break
	x1 = x0 + w
	y1 = y0 + h
	# No spot leaves a way through: this band has no island this time.
	if not found:
		alive = false


## Whether an island in this box would leave the bird no fair way: on its
## first hop or in its start lane (before the first tap), in front of the wall
## it comes out of (portal or revive), too close under the island above, or in
## front of an exit that is already there (revive).
func _in_the_way(sim: GameSim, bx0: int, by0: int, bx1: int, by1: int) -> bool:
	return (
		sim.start_path_hits_rect(bx0, by0, bx1, by1, START_MARGIN)
		or sim.blocks_start_lane(bx0, by0, bx1, by1)
		or _blocks_arrival(sim, bx0, by0, bx1, by1)
		or _crowds_neighbour(sim, bx0, by0, bx1)
		or _covers_exit(sim, bx0, by0, bx1, by1)
	)


## Whether a box is in front of an exit that is open or planned (a ghost).
func _covers_exit(sim: GameSim, bx0: int, by0: int, bx1: int, by1: int) -> bool:
	var st := sim.state
	if not st.exit_open and not st.exit_preview:
		return false
	if _fronts_exit(sim, st.exit_side, st.exit_a_y, EXIT_ROOM, bx0, by0, bx1, by1):
		return true
	return (
		st.exit_b_kind != SimState.ExitKind.NORMAL
		and _fronts_exit(sim, st.exit_side, st.exit_b_y, EXIT_ROOM, bx0, by0, bx1, by1)
	)


## The room starts with the bird already flying only when it comes out of a
## wall (through a portal or on a revive): at its height, flying level, from
## the wall behind it. Whether a box is in its arrival lane, or, when the bird
## is revived facing an open exit (it has one flight to get there), anywhere
## between its height and the exit's.
func _blocks_arrival(sim: GameSim, bx0: int, by0: int, bx1: int, by1: int) -> bool:
	var st := sim.state
	if not st.started:
		return false
	var up := st.y - ARRIVAL_UP * sim.room.def.gravity_sign
	var down := st.y + ARRIVAL_DOWN * sim.room.def.gravity_sign
	var top := mini(up, down)
	var bottom := maxi(up, down)
	if by1 > top and by0 < bottom:
		if st.vx > 0 and bx0 < sim.room.wall_left() + ARRIVAL_W:
			return true
		if st.vx < 0 and bx1 > sim.room.wall_right() - ARRIVAL_W:
			return true
	if not st.exit_open:
		return false
	top = mini(top, st.exit_a_y - ARRIVAL_UP)
	bottom = maxi(bottom, st.exit_a_y + ARRIVAL_UP)
	if st.exit_b_kind != SimState.ExitKind.NORMAL:
		top = mini(top, st.exit_b_y - ARRIVAL_UP)
		bottom = maxi(bottom, st.exit_b_y + ARRIVAL_UP)
	return by1 > top and by0 < bottom


## The island of the band above, as [x0, x1, y1]; empty if there is none.
func _neighbour(sim: GameSim) -> PackedInt32Array:
	for other in sim.room.hazards:
		if other != self and other.kind == kind and other.alive and other.band == band - 1:
			return PackedInt32Array([other.x0, other.x1, other.y1])
	return PackedInt32Array()


## Whether a box would sit over or under the island of the band above (or
## within PINCH_X of its ends) with less than MIN_GAP between them: the bird
## can't hold its height in a slot thinner than about one hop.
func _crowds_neighbour(sim: GameSim, bx0: int, by0: int, bx1: int) -> bool:
	var other := _neighbour(sim)
	if other.is_empty():
		return false
	var beside := bx0 - other[1] >= PINCH_X or other[0] - bx1 >= PINCH_X
	return not beside and by0 - other[2] < MIN_GAP


## Whether a box is in front of an exit at height `y` on wall `side`: close to
## that wall and within `margin` of a bird flying level into the exit's middle.
func _fronts_exit(
	sim: GameSim, side: int, y: int, margin: int, bx0: int, by0: int, bx1: int, by1: int
) -> bool:
	var away := bx0 - sim.room.wall_left() if side == 0 else sim.room.wall_right() - bx1
	if away >= EXIT_CLEAR_X:
		return false
	var reach := SimConfig.BIRD_RADIUS + margin
	return by1 + reach > y and by0 - reach < y


## No exit opens level with an island that sits near its wall.
func blocks_exit(sim: GameSim, side: int, y: int) -> bool:
	if band < 0:
		return false
	return _fronts_exit(sim, side, y, EXIT_MARGIN, x0, y0, x1, y1)


func solid() -> bool:
	if fade_period <= 0:
		return true
	return posmod(t + phase, fade_period) < solid_ticks


## 0..1024 how visible it is (fading blocks warn before turning solid).
func opacity() -> int:
	if fade_period <= 0:
		return SimTrig.ONE
	var p := posmod(t + phase, fade_period)
	if p < solid_ticks:
		return SimTrig.ONE
	var fade := fade_period - solid_ticks
	var into := p - solid_ticks
	# Fades out over the first third, back in over the last third.
	var third := maxi(fade / 3, 1)
	if into < third:
		return SimTrig.ONE - SimTrig.ONE * into / third
	if into > fade - third:
		return SimTrig.ONE * (into - (fade - third)) / third
	return 0


func kills(sim: GameSim) -> bool:
	return solid() and sim.bird_touches_rect(x0, y0, x1, y1)


func checksum(h: int) -> int:
	return mix_all(h, [x0, y0, x1, y1, fade_period, solid_ticks, phase])
