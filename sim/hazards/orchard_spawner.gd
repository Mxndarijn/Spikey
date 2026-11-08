extends Hazard
## Orchard Drop's coins: every SPAWN_EVERY steps a coin starts falling from just
## above the ceiling in one of five columns (picked by its own SimRng, seeded in
## setup()). Fly through one to collect it; missed coins fall out of the room.

const SUB := SimConfig.SUB
const SPAWN_EVERY := 36
const FALL := 2 * SUB
const SLOTS := 12
const START_Y := 24 * SUB
const COLUMNS: Array[int] = [80 * SUB, 130 * SUB, 180 * SUB, 230 * SUB, 280 * SUB]

## Coin slots: position and whether it is falling now.
var xs: Array[int] = []
var ys: Array[int] = []
var live: Array[bool] = []
var _rng := SimRng.new()


func _init() -> void:
	kind = "orchard_spawner"
	for i in SLOTS:
		xs.append(0)
		ys.append(0)
		live.append(false)


func setup(_sim: GameSim, rng: SimRng) -> void:
	_rng.reseed(rng.next_u32())


func step(_sim: GameSim) -> void:
	for i in SLOTS:
		if live[i]:
			ys[i] += FALL
			if ys[i] > SimConfig.KILL_BOTTOM + SimConfig.COIN_RADIUS:
				live[i] = false
	if t % SPAWN_EVERY == 1:
		for i in SLOTS:
			if not live[i]:
				live[i] = true
				xs[i] = COLUMNS[_rng.next_below(COLUMNS.size())]
				ys[i] = START_Y
				break


func touch(sim: GameSim) -> void:
	for i in SLOTS:
		if live[i] and sim.bird_touches_circle(xs[i], ys[i], SimConfig.COIN_RADIUS):
			live[i] = false
			sim.collect_coin(xs[i], ys[i])


func live_count() -> int:
	var n := 0
	for v in live:
		n += int(v)
	return n


func checksum(h: int) -> int:
	var out := SimHash.mix(h, _rng.state_checksum())
	for i in SLOTS:
		out = mix_all(out, [xs[i], ys[i], int(live[i])])
	return out
