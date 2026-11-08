extends Hazard
## Crates that drop one at a time from the top and pile up in columns (Crate
## Drop). A marker shows where the next crate will fall. Falling crates and the
## stacks kill. Stacks never grow past MAX_HEIGHT, so the bird can always fly
## over them. With `gifts` (Winter Gift Stack) a coin sits on top of each new
## stack until the bird takes it.

const COLS := 7
## Column 0 starts here; columns are COL_W wide, clear of the wall spikes.
const COL_X0 := 40 * SimConfig.SUB
const COL_W := 40 * SimConfig.SUB
## Crates are square, a little narrower than a column.
const CRATE := 36 * SimConfig.SUB
const MAX_HEIGHT := 4
## Where stacks stand (the floor kill line).
const FLOOR := SimConfig.KILL_BOTTOM
const START_DELAY := 20
const WARN_TICKS := 45
const FALL_ACCEL := 20
const MAX_FALL := 9 * SimConfig.SUB
## Gap between a stack's top and the coin sitting on it.
const COIN_LIFT := 4 * SimConfig.SUB

## Column of the crate being dropped, or -1 once every column is full.
var col := -1
## Top of the falling crate and its speed, sub-units.
var y := 0
var vy := 0
## Steps of warning left before the crate falls (0 = falling).
var warn_left := 0
## Crates dropped so far (picks the next column with `salt`).
var drops := 0
var salt := 0
## Crates in each column.
var heights: Array[int] = []
## 1 where a coin sits on that column's stack.
var coins: Array[int] = []
## Winter Gift Stack: a coin on top of each new stack.
var gifts := false


func _init(p_gifts: bool = false) -> void:
	kind = "crate_drop"
	gifts = p_gifts
	heights.resize(COLS)
	heights.fill(0)
	coins.resize(COLS)
	coins.fill(0)


func setup(_sim: GameSim, rng: SimRng) -> void:
	if skin == "gift":
		gifts = true
	salt = rng.next_u32()
	_next_drop(START_DELAY + WARN_TICKS)


func _next_drop(warn: int) -> void:
	col = -1
	var start := posmod(SimHash.mix(salt, drops), COLS)
	for i in COLS:
		var c := (start + i) % COLS
		if heights[c] < MAX_HEIGHT:
			col = c
			break
	drops += 1
	y = -CRATE
	vy = 0
	warn_left = warn


func step(_sim: GameSim) -> void:
	if col < 0:
		return
	if warn_left > 0:
		warn_left -= 1
		return
	vy = mini(vy + FALL_ACCEL, MAX_FALL)
	y += vy
	var land := stack_top(col) - CRATE
	if y >= land:
		y = land
		heights[col] += 1
		if gifts and heights[col] == 1:
			coins[col] = 1
		_next_drop(WARN_TICKS)


func falling() -> bool:
	return col >= 0 and warn_left == 0


func col_left(c: int) -> int:
	return COL_X0 + c * COL_W + (COL_W - CRATE) / 2


func col_center(c: int) -> int:
	return COL_X0 + c * COL_W + COL_W / 2


## Top of the stack in column c (the floor when empty).
func stack_top(c: int) -> int:
	return FLOOR - heights[c] * CRATE


func coin_y(c: int) -> int:
	return stack_top(c) - COIN_LIFT - SimConfig.COIN_RADIUS


func kills(sim: GameSim) -> bool:
	if falling():
		var x := col_left(col)
		if sim.bird_touches_rect(x, y, x + CRATE, y + CRATE):
			return true
	for c in COLS:
		if heights[c] > 0:
			var x := col_left(c)
			if sim.bird_touches_rect(x, stack_top(c), x + CRATE, SimConfig.WORLD_H):
				return true
	return false


func touch(sim: GameSim) -> void:
	for c in COLS:
		if (
			coins[c] == 1
			and sim.bird_touches_circle(col_center(c), coin_y(c), SimConfig.COIN_RADIUS)
		):
			coins[c] = 0
			sim.collect_coin(col_center(c), coin_y(c))


func checksum(h: int) -> int:
	var out := mix_all(h, [col, y, vy, warn_left, drops, salt, int(gifts)])
	out = mix_all(out, heights)
	return mix_all(out, coins)
