extends Hazard
## Crates that drop one at a time from the top and pile up in columns (Crate
## Drop). A marker shows where the next crate will fall. Falling crates and the
## stacks kill. Stacks never grow past MAX_HEIGHT, so the bird can always fly
## over them. With `gifts` (Winter Gift Stack) a coin sits on top of each new
## stack until the bird takes it.
##
## Variants: bigger crates in fewer columns (cols, col_w, crate_w, crate_h,
## max_height), or two crates falling at once in different columns (pair).
##
## No crate falls down a column through an open or ghost exit's mouth
## (ExitZone); one already falling when the exit appears breaks on it.

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
## A column isn't marked if the bird, flying on, first reaches its crate's
## kill range from the end of the warning to FAIR_SPAN steps later: it could
## neither pass under the falling crate and out before it lands, nor have had
## time to climb over it. When every free column is like that, the usual pick.
const FAIR_SPAN := 50

## Columns, their width and the crates' size; stacks never get taller than
## max_height crates. The columns sit in the middle of the room.
var cols := COLS
var col_w := COL_W
var col_x0 := COL_X0
var crate_w := CRATE
var crate_h := CRATE
var max_height := MAX_HEIGHT
## Two crates fall at once (the second one is crate "b").
var pair := false

## Column of the crate being dropped, or -1 once every column is full.
var col := -1
## Top of the falling crate and its speed, sub-units.
var y := 0
var vy := 0
## The crate has landed (with a pair it waits for crate b).
var done := false
## Pair: crate b's column (-1 = none), top, speed and whether it has landed.
var col_b := -1
var y_b := 0
var vy_b := 0
var done_b := false
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


func _init(
	p_gifts: bool = false,
	p_cols: int = COLS,
	p_col_w: int = COL_W,
	p_crate_w: int = CRATE,
	p_crate_h: int = CRATE,
	p_max_height: int = MAX_HEIGHT,
	p_pair: bool = false
) -> void:
	kind = "crate_drop"
	gifts = p_gifts
	cols = p_cols
	col_w = p_col_w
	col_x0 = (SimConfig.WORLD_W - cols * col_w) / 2
	crate_w = p_crate_w
	crate_h = p_crate_h
	max_height = p_max_height
	pair = p_pair
	heights.resize(cols)
	heights.fill(0)
	coins.resize(cols)
	coins.fill(0)


func setup(_sim: GameSim, rng: SimRng) -> void:
	salt = rng.next_u32()
	_next_drop(null, START_DELAY + WARN_TICKS)


## `sim` null: before the room's exits are known (setup).
func _next_drop(sim: GameSim, warn: int) -> void:
	col = _free_col(sim, posmod(SimHash.mix(salt, drops), cols), -1, warn)
	col_b = -1
	if pair and col >= 0:
		# The second crate falls about half the room away.
		col_b = _free_col(sim, (col + cols / 2) % cols, col, warn)
	drops += 1
	y = -crate_h
	vy = 0
	done = false
	y_b = y
	vy_b = 0
	done_b = false
	warn_left = warn


## The first column from `start` on (wrapping) that is not full, not `skip`,
## not falling through an exit's mouth (ExitZone) and fair to a bird `warn`
## steps before the crate falls (_fair_col); without a fair one, the first of
## the others.
func _free_col(sim: GameSim, start: int, skip: int, warn: int) -> int:
	var first := -1
	for i in cols:
		var c := (start + i) % cols
		if c != skip and heights[c] < max_height and (sim == null or not _col_in_exit(sim, c)):
			if sim == null or _fair_col(sim, c, warn):
				return c
			if first < 0:
				first = c
	return first


## False if the bird first reaches column c's kill range in x while its crate,
## warned for `warn` steps, falls (FAIR_SPAN).
func _fair_col(sim: GameSim, c: int, warn: int) -> bool:
	var e := entry_steps(sim, c, warn + FAIR_SPAN + 1)
	return e < warn or e > warn + FAIR_SPAN


## Steps until the bird, flying on (its x doesn't depend on taps), first
## overlaps column c's crate in x, widened by the bird's radius; `limit` if not
## before then.
func entry_steps(sim: GameSim, c: int, limit: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var lo := col_left(c) - r
	var hi := col_left(c) + crate_w + r
	var x := sim.state.x
	var vx := sim.state.vx
	var left := sim.room.wall_left()
	var right := sim.room.wall_right()
	for s in limit:
		if x >= lo and x <= hi:
			return s
		x += vx
		if vx > 0 and x + r >= right:
			x = 2 * (right - r) - x
			vx = -vx
		elif vx < 0 and x - r <= left:
			x = 2 * (left + r) - x
			vx = -vx
	return limit


## True if a crate falling down column c touches an open or ghost exit's mouth.
func _col_in_exit(sim: GameSim, c: int) -> bool:
	var x := col_left(c)
	return ExitZone.hits_rect(sim, x, -crate_h, x + crate_w, FLOOR)


func step(sim: GameSim) -> void:
	if col < 0:
		return
	# The first crate was marked before the room's exits and the bird were
	# known: mark it again (the same pick, now past the exits and fair) if it
	# would fall through an exit's mouth or be unfair to the bird (_fair_col).
	if (
		t == 1
		and (
			_col_in_exit(sim, col)
			or col_b >= 0 and _col_in_exit(sim, col_b)
			or not _fair_col(sim, col, warn_left)
			or col_b >= 0 and not _fair_col(sim, col_b, warn_left)
		)
	):
		drops -= 1
		_next_drop(sim, warn_left)
		if col < 0:
			return
	if warn_left > 0:
		warn_left -= 1
		return
	# A crate breaks on an exit's mouth that opened in its way (ExitZone).
	if not done and _crate_in_exit(sim, col, y):
		done = true
	if col_b >= 0 and not done_b and _crate_in_exit(sim, col_b, y_b):
		done_b = true
	if not done:
		vy = mini(vy + FALL_ACCEL, MAX_FALL)
		y += vy
		var land := stack_top(col) - crate_h
		if y >= land:
			y = land
			_land(col)
			done = true
	if col_b >= 0 and not done_b:
		vy_b = mini(vy_b + FALL_ACCEL, MAX_FALL)
		y_b += vy_b
		var land_b := stack_top(col_b) - crate_h
		if y_b >= land_b:
			y_b = land_b
			_land(col_b)
			done_b = true
	if done and (col_b < 0 or done_b):
		_next_drop(sim, WARN_TICKS)


func _crate_in_exit(sim: GameSim, c: int, top: int) -> bool:
	var x := col_left(c)
	return ExitZone.hits_rect(sim, x, top, x + crate_w, top + crate_h)


func _land(c: int) -> void:
	heights[c] += 1
	if gifts and heights[c] == 1:
		coins[c] = 1


func falling() -> bool:
	return col >= 0 and warn_left == 0


## No exit level with where the tallest stack can reach (a slot over its top):
## the columns run close to both walls, so a bird can't dip under a stack
## into a low exit.
func blocks_exit(_sim: GameSim, _side: int, y: int) -> bool:
	return y > FLOOR - max_height * crate_h - SimConfig.SLOT_SIZE


func col_left(c: int) -> int:
	return col_x0 + c * col_w + (col_w - crate_w) / 2


func col_center(c: int) -> int:
	return col_x0 + c * col_w + col_w / 2


## Top of the stack in column c (the floor when empty).
func stack_top(c: int) -> int:
	return FLOOR - heights[c] * crate_h


func coin_y(c: int) -> int:
	return stack_top(c) - COIN_LIFT - SimConfig.COIN_RADIUS


func kills(sim: GameSim) -> bool:
	if falling():
		if not done:
			var x := col_left(col)
			if sim.bird_touches_rect(x, y, x + crate_w, y + crate_h):
				return true
		if col_b >= 0 and not done_b:
			var xb := col_left(col_b)
			if sim.bird_touches_rect(xb, y_b, xb + crate_w, y_b + crate_h):
				return true
	for c in cols:
		if heights[c] > 0:
			var x := col_left(c)
			if sim.bird_touches_rect(x, stack_top(c), x + crate_w, SimConfig.WORLD_H):
				return true
	return false


func touch(sim: GameSim) -> void:
	for c in cols:
		if (
			coins[c] == 1
			and sim.bird_touches_circle(col_center(c), coin_y(c), SimConfig.COIN_RADIUS)
		):
			coins[c] = 0
			sim.collect_coin(col_center(c), coin_y(c))


func checksum(h: int) -> int:
	var out := mix_all(h, [col, y, vy, warn_left, drops, salt, int(gifts)])
	if pair:
		out = mix_all(out, [col_b, y_b, vy_b, int(done), int(done_b)])
	out = mix_all(out, heights)
	return mix_all(out, coins)


## While the marker shows: the column each marked crate falls down, from the
## top of the room to its stack, for the fall. (The stack it leaves is a
## thing on screen by then, not a warning.)
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if col < 0 or warn_left <= 0:
		return
	_warn_col(out, col)
	if col_b >= 0:
		_warn_col(out, col_b)


func _warn_col(out: PackedInt64Array, c: int) -> void:
	var land := stack_top(c) - crate_h
	# Steps of the fall, as step() moves the crate.
	var top := -crate_h
	var speed := 0
	var dur := 0
	while top < land:
		speed = mini(speed + FALL_ACCEL, MAX_FALL)
		top += speed
		dur += 1
	var x := col_left(c)
	add_warning(out, x, -crate_h, x + crate_w, stack_top(c), warn_left, dur, WARN_KILL)
