extends TestCase
## The coin and bubble room variants: Bubble Lift (giants, spiky,
## coin-bubbles), Coin Garden (orbit, decoy) and Slow-Mo Breather (zigzag).

const Bubble := preload("res://sim/hazards/bubble.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")
const SpikeBall := preload("res://sim/hazards/spike_ball.gd")

const SUB := SimConfig.SUB
const VARIANTS := {
	"bubbles": ["classic", "giants", "spiky", "coin-bubbles"],
	"garden": ["classic", "orbit", "decoy"],
	"slowmo": ["classic", "zigzag"],
}


## A practice sim of room `id` playing variant `variant`.
static func in_variant(id: String, variant: String, seed_value: int = 3) -> GameSim:
	return GameSim.new(seed_value, Seasons.NONE, RoomCatalog.index_of(id), variant)


## A started sim (the bird flying) of room `id` in `variant`, the bird parked
## out of the way at the left wall.
static func started(id: String, variant: String, seed_value: int = 3) -> GameSim:
	var sim := in_variant(id, variant, seed_value)
	sim.state.started = true
	return sim


static func of_kind(sim: GameSim, kind: String) -> Array[Hazard]:
	var out: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.alive and h.kind == kind:
			out.append(h)
	return out


## Holds the bird still at (x, y).
static func park(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y
	sim.state.vx = 0
	sim.state.vy = 0


func test_variants_are_listed_and_drawn() -> void:
	for id: String in VARIANTS:
		var def := RoomCatalog.find(id)
		var ids := []
		for v in def.variants:
			ids.append(v.id)
		assert_eq(ids, VARIANTS[id], "%s variants" % id)
		var seen := {}
		for s in 200:
			var sim := GameSim.new(s, Seasons.NONE, RoomCatalog.index_of(id))
			seen[sim.room.variant_id()] = true
		assert_eq(seen.size(), def.variants.size(), "%s: every variant is drawn" % id)


## Every room coin of these variants sits in the coin band, clear of the
## ceiling and the floor, for the whole room.
func test_coins_stay_in_the_coin_band() -> void:
	for id: String in VARIANTS:
		for v: String in VARIANTS[id]:
			var sim := started(id, v)
			for i in 900:
				sim.room.step(sim)
				for h in of_kind(sim, "coin"):
					var c := h as CoinPickup
					if not c.visible():
						continue
					var what := "%s/%s step %d" % [id, v, i]
					assert_between(c.y, SimConfig.COIN_MIN_Y, SimConfig.COIN_MAX_Y, what)
					assert_between(c.x, SimConfig.COIN_MIN_X, SimConfig.COIN_MAX_X, what)


func test_giants_are_big_and_slow_and_still_carry() -> void:
	var sim := started("bubbles", "giants")
	var bubbles := of_kind(sim, "bubble")
	assert_eq(bubbles.size(), 3)
	var b := bubbles[0] as Bubble
	assert_eq(b.radius, Bubble.GIANT_RADIUS)
	assert_true(b.radius > Bubble.RADIUS, "bigger than a normal bubble")
	assert_true(-b.vy < Bubble.RISE, "slower than a normal bubble")
	b.y = 450 * SUB
	park(sim, b.x, b.y)
	sim.step(false)
	assert_true(b.carrying, "a giant carries the bird")
	var y0 := sim.state.y
	for i in 10:
		sim.step(false)
	assert_eq(y0 - sim.state.y, 10 * Bubble.GIANT_RISE, "at the giant's speed")


func test_spiked_bubbles_wait_marked_under_the_floor_then_kill() -> void:
	var sim := started("bubbles", "spiky")
	var spiked: Array[Bubble] = []
	var safe := 0
	for h in of_kind(sim, "bubble"):
		var b := h as Bubble
		if b.spiked:
			spiked.append(b)
		else:
			safe += 1
	assert_eq(spiked.size(), 2, "two spiked bubbles")
	assert_eq(safe, 2, "and two safe ones")
	for b in spiked:
		assert_true(b.y > SimConfig.WORLD_H, "starts under the floor")
		assert_true(b.wait >= Bubble.WARN, "waits at least a second first")
	assert_true(spiked[1].wait > spiked[0].wait, "their rises are spread out")
	var b := spiked[0]
	park(sim, 20 * SUB, 300 * SUB)
	# While it waits, it doesn't move and can't kill.
	var y0 := b.y
	for i in b.wait - 1:
		sim.room.step(sim)
	assert_eq(b.y, y0, "waits in place")
	assert_eq(b.wait, 1)
	sim.room.step(sim)
	sim.room.step(sim)
	assert_true(b.y < y0, "then rises")
	# It kills on touch and never carries.
	b.y = 400 * SUB
	park(sim, b.x, b.y)
	assert_true(b.kills(sim), "a spiked bubble kills")
	b.touch(sim)
	assert_false(b.carrying, "and never carries")
	# Popped at the top, it waits under the floor again.
	b.pop()
	assert_eq(b.wait, Bubble.WARN, "a second's warning before every rise")
	assert_false(b.kills(sim))


func test_spiked_bubbles_never_hit_a_bird_that_just_came_in() -> void:
	for s in 40:
		var sim := started("bubbles", "spiky", s)
		for x: int in [24 * SUB, SimConfig.WORLD_W - 24 * SUB]:
			for y_px in range(80, 600, 20):
				park(sim, x, y_px * SUB)
				for h in sim.room.hazards:
					assert_false(h.kills(sim), "seed %d" % s)


func test_coin_bubbles_bring_a_coin_on_every_rise() -> void:
	var sim := started("bubbles", "coin-bubbles")
	var bubbles := of_kind(sim, "bubble")
	assert_eq(bubbles.size(), 3)
	var with_coin := 0
	for h in bubbles:
		if (h as Bubble).has_coin:
			with_coin += 1
	assert_eq(with_coin, 2, "every other bubble has a coin")
	var b := bubbles[0] as Bubble
	assert_true(b.has_coin)
	# Out of the coin band (near the floor) the coin can't be taken.
	b.y = SimConfig.COIN_MAX_Y + 20 * SUB
	park(sim, b.x, b.y)
	b.touch(sim)
	assert_true(b.has_coin, "not taken near the floor")
	assert_eq(sim.state.coins, 0)
	b.carrying = false
	b.y = 400 * SUB
	park(sim, b.x, b.y)
	sim.step(false)
	assert_false(b.has_coin, "flying into the bubble takes its coin")
	assert_eq(sim.state.coins, 1)
	assert_true(b.carrying, "and it still carries the bird")
	sim.step(true)
	assert_true(b.has_coin, "the next rise brings a new coin")


func test_orbiting_coins_turn_around_the_middle() -> void:
	var sim := started("garden", "orbit")
	var coins := of_kind(sim, "coin")
	assert_eq(coins.size(), 4)
	var c := coins[0] as CoinPickup
	var x0 := c.x
	var y0 := c.y
	for i in 60:
		sim.room.step(sim)
	assert_true(c.x != x0 or c.y != y0, "the diamond turns")
	park(sim, c.x, c.y)
	c.touch(sim)
	assert_false(c.alive, "an orbiting coin is taken like any coin")
	assert_eq(sim.state.coins, 1)


func test_decoy_is_a_spike_ball_on_a_coin_spot() -> void:
	for s in 30:
		var sim := in_variant("garden", "decoy", s)
		var balls := of_kind(sim, "spike_ball")
		assert_eq(balls.size(), 1, "one spiked ball")
		assert_eq(of_kind(sim, "coin").size(), 3, "and three coins")
		var ball := balls[0] as SpikeBall
		var on_spot := false
		for i in range(0, ball.spots.size(), 2):
			on_spot = on_spot or (ball.spots[i] == ball.x and ball.spots[i + 1] == ball.y)
		assert_true(on_spot, "the ball sits on a coin spot")
		for h in of_kind(sim, "coin"):
			var c := h as CoinPickup
			assert_false(c.x == ball.x and c.y == ball.y, "no coin under the ball")
		park(sim, ball.x, ball.y)
		assert_true(ball.kills(sim), "the ball kills")


## A practice start (the bird at the left wall, about to hop in) never has
## the ball on its first hop or in its start lane.
func test_decoy_keeps_off_the_start_lane() -> void:
	for s in 60:
		var sim := in_variant("garden", "decoy", s)
		var ball := of_kind(sim, "spike_ball")[0] as SpikeBall
		var r := SpikeBall.RADIUS
		assert_false(
			FairLanes.blocks_start_lane(sim, ball.x - r, ball.y - r, ball.x + r, ball.y + r),
			"seed %d: start lane clear" % s
		)
		assert_false(
			FairLanes.start_path_hits_rect(sim, ball.x - r, ball.y - r, ball.x + r, ball.y + r, 0),
			"seed %d: first hop clear" % s
		)


func test_zigzag_coins_alternate_high_and_low() -> void:
	var sim := in_variant("slowmo", "zigzag")
	var coins := of_kind(sim, "coin")
	assert_eq(coins.size(), 5)
	for i in coins.size():
		var c := coins[i] as CoinPickup
		assert_eq(c.x, (90 + i * 45) * SUB)
		assert_eq(c.y, (380 if i % 2 == 1 else 280) * SUB, "coin %d" % i)
