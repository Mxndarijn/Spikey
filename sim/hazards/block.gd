extends Hazard
## A still box in the room (Floating Isles). With `fade_period` set it fades in
## and out on a cycle and is only deadly while solid (Ghost Doors).

## Floating Isles bands (see `band`).
const BAND := 110 * SimConfig.SUB
const BAND_TOP := 96 * SimConfig.SUB
## Room kept between an island and the bird's first hop.
const START_MARGIN := 6 * SimConfig.SUB
## Least clear height between islands in neighbouring bands that overlap side
## to side.
const MIN_GAP := 95 * SimConfig.SUB

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
	x0 = 80 * sub + rng.next_below(200 * sub - w)
	y0 = BAND_TOP + band * BAND + 10 * sub + rng.next_below(BAND - h - 20 * sub)
	# Off the bird's first hop: try the top or bottom of the band first, then
	# the far end (no extra draws, so the seed still decides everything).
	var band_top := BAND_TOP + band * BAND + 10 * sub
	var band_bottom := BAND_TOP + (band + 1) * BAND - 10 * sub - h
	var far_x := 280 * sub - w
	var near_x := 80 * sub
	# Spots to try, as x, y pairs.
	var spots: Array[int] = []
	for sx in [x0, far_x, near_x]:
		for sy in [y0, band_top, band_bottom]:
			spots.append(sx)
			spots.append(sy)
	# Best: a way between it and the island above, off the first hop and clear
	# of the start lane; then drop the lane. If no spot keeps a way past the
	# island above, this band has no island this time.
	var found := false
	for rule in 2:
		for i in range(0, spots.size(), 2):
			var cx := spots[i]
			var cy := spots[i + 1]
			if sim.start_path_hits_rect(cx, cy, cx + w, cy + h, START_MARGIN):
				continue
			if rule == 0 and sim.blocks_start_lane(cx, cy, cx + w, cy + h):
				continue
			if _crowds_neighbour(sim, cx, cy, cx + w):
				continue
			x0 = cx
			y0 = cy
			found = true
			break
		if found:
			break
	x1 = x0 + w
	y1 = y0 + h
	if not found:
		alive = false


## Whether a box would sit over or under the island of the band above with
## less than MIN_GAP between them (the bird can't hold its height in a slot
## thinner than about one hop).
func _crowds_neighbour(sim: GameSim, bx0: int, by0: int, bx1: int) -> bool:
	for other in sim.room.hazards:
		if other == self or other.kind != kind or other.band != band - 1:
			continue
		var overlap: bool = bx1 > other.x0 and bx0 < other.x1
		if overlap and by0 - other.y1 < MIN_GAP:
			return true
	return false


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
