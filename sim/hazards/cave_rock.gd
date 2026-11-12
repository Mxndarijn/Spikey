extends Hazard
## Cave Tunnel's rock: a ceiling rock and a floor rock that leave one tunnel,
## and (fork) a rock island splitting its far end in two. Built once by the
## room's recipe (CatalogCaves) and never changed: nothing here moves. All of
## it kills, exactly where it is drawn: each face is one polyline whose
## points include the fangs (two-tone in the painter, the same outline).
##
## top_x/top_y: the ceiling rock's lower edge, left to right from x 0 to
## WORLD_W; above it is rock. bot_x/bot_y: the floor rock's upper edge; below
## it is rock. isle_x/isle_top/isle_bot: the island's upper and lower edges at
## the same x's, left to right; between them is rock (empty = no island).

## Wall spikes keep at least this many free slots in a row inside a mouth.
const FREE_RUN := 3
## An exit's box (ExitZone) keeps this much room inside a mouth.
const EXIT_MARGIN := 4 * SimConfig.SUB
## A mouth is measured over the exit box's depth, this often.
const MOUTH_STEP := 4 * SimConfig.SUB

var top_x := PackedInt32Array()
var top_y := PackedInt32Array()
var bot_x := PackedInt32Array()
var bot_y := PackedInt32Array()
var isle_x := PackedInt32Array()
var isle_top := PackedInt32Array()
var isle_bot := PackedInt32Array()


func _init() -> void:
	kind = "cave_rock"


## Height of polyline (xs, ys) at `x` (clamped to its ends).
static func edge_at(xs: PackedInt32Array, ys: PackedInt32Array, x: int) -> int:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			var span := xs[i] - xs[i - 1]
			if span <= 0:
				return ys[i]
			return ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / span
	return ys[ys.size() - 1]


## Whether the bird touches polyline (xs, ys) or is past it (`below`: under
## it is rock; else over it is rock). Only the segments near the bird count.
static func _hits_face(
	sim: GameSim, xs: PackedInt32Array, ys: PackedInt32Array, below: bool
) -> bool:
	var bx := sim.state.x
	var by := sim.state.y
	var r := SimConfig.BIRD_RADIUS
	var at := edge_at(xs, ys, bx)
	if (by > at) if below else (by < at):
		return true
	for i in range(1, xs.size()):
		if xs[i] < bx - r or xs[i - 1] > bx + r:
			continue
		if SimMath.circle_hits_segment(bx, by, r, xs[i - 1], ys[i - 1], xs[i], ys[i]):
			return true
	return false


## Whether the bird touches the island or is inside it.
func _hits_isle(sim: GameSim) -> bool:
	if isle_x.is_empty():
		return false
	var bx := sim.state.x
	var by := sim.state.y
	var r := SimConfig.BIRD_RADIUS
	if bx + r < isle_x[0]:
		return false
	if (
		bx >= isle_x[0]
		and by > edge_at(isle_x, isle_top, bx)
		and by < edge_at(isle_x, isle_bot, bx)
	):
		return true
	for i in range(1, isle_x.size()):
		if isle_x[i] < bx - r or isle_x[i - 1] > bx + r:
			continue
		var x0 := isle_x[i - 1]
		var x1 := isle_x[i]
		if SimMath.circle_hits_segment(bx, by, r, x0, isle_top[i - 1], x1, isle_top[i]):
			return true
		if SimMath.circle_hits_segment(bx, by, r, x0, isle_bot[i - 1], x1, isle_bot[i]):
			return true
	return false


func kills(sim: GameSim) -> bool:
	return (
		_hits_face(sim, top_x, top_y, false)
		or _hits_face(sim, bot_x, bot_y, true)
		or _hits_isle(sim)
	)


## The open stretches ("mouths") of wall `side`, top and bottom of each, as
## pairs: the tunnel's, or the two branches' where the island meets the wall.
## Measured over an exit box's depth (ExitZone.DEPTH), fangs included.
func mouths(side: int) -> PackedInt32Array:
	var wx := 0 if side == 0 else SimConfig.WORLD_W
	var dir := 1 if side == 0 else -1
	var top := -SimConfig.WORLD_H
	var bottom := 2 * SimConfig.WORLD_H
	var isle_top_y := 2 * SimConfig.WORLD_H
	var isle_bot_y := -SimConfig.WORLD_H
	var isle := false
	for d in range(0, ExitZone.DEPTH + 1, MOUTH_STEP):
		var x := wx + dir * d
		top = maxi(top, edge_at(top_x, top_y, x))
		bottom = mini(bottom, edge_at(bot_x, bot_y, x))
		if not isle_x.is_empty() and x >= isle_x[0] and x <= isle_x[isle_x.size() - 1]:
			isle = true
			isle_top_y = mini(isle_top_y, edge_at(isle_x, isle_top, x))
			isle_bot_y = maxi(isle_bot_y, edge_at(isle_x, isle_bot, x))
	if not isle or isle_bot_y <= isle_top_y:
		return PackedInt32Array([top, bottom])
	return PackedInt32Array([top, isle_top_y, isle_bot_y, bottom])


## An exit goes only where its whole box (ExitZone) fits in a mouth.
func blocks_exit(_sim: GameSim, side: int, y: int) -> bool:
	var m := mouths(side)
	var keep := ExitZone.HALF + EXIT_MARGIN
	for i in range(0, m.size(), 2):
		if y >= m[i] + keep and y <= m[i + 1] - keep:
			return false
	return true


## No wall spike in the rock (it is rock there), and inside each mouth a free
## run of FREE_RUN slots in a row, round the mouth's middle if the wall had
## none. No RNG.
func adjust_wall(_sim: GameSim, side: int, mask: int) -> int:
	var out := mask
	var half := SimConfig.SPIKE_HALF_BASE
	var m := mouths(side)
	for slot in SimConfig.SLOT_COUNT:
		var yc := SimConfig.slot_center_y(slot)
		var open := false
		for i in range(0, m.size(), 2):
			if yc + half > m[i] and yc - half < m[i + 1]:
				open = true
		if not open:
			out &= ~(1 << slot)
	for i in range(0, m.size(), 2):
		out = _free_run(out, m[i], m[i + 1])
	return out


## `mask` with a run of FREE_RUN free slots inside mouth top..bottom: kept if
## it has one, else the slots nearest the mouth's middle cleared.
static func _free_run(mask: int, top: int, bottom: int) -> int:
	var half := SimConfig.SPIKE_HALF_BASE
	var first := -1
	var last := -1
	for slot in SimConfig.SLOT_COUNT:
		var yc := SimConfig.slot_center_y(slot)
		if yc - half >= top and yc + half <= bottom:
			if first < 0:
				first = slot
			last = slot
	if first < 0:
		return mask
	var run := 0
	for slot in range(first, last + 1):
		run = 0 if (mask & (1 << slot)) != 0 else run + 1
		if run >= FREE_RUN:
			return mask
	var out := mask
	var mid := (first + last) / 2
	var lo := clampi(mid - FREE_RUN / 2, first, maxi(first, last - FREE_RUN + 1))
	for slot in range(lo, mini(lo + FREE_RUN, last + 1)):
		out &= ~(1 << slot)
	return out


func checksum(h: int) -> int:
	var out := mix_all(h, [top_x.size(), bot_x.size(), isle_x.size()])
	out = mix_all(out, Array(top_y) + Array(bot_y) + Array(isle_top) + Array(isle_bot))
	return mix_all(out, Array(top_x) + Array(bot_x) + Array(isle_x))
