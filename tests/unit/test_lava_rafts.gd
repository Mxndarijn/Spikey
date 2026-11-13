extends TestCase
## Lava Rise's Rafts, rising two steps a point with no cap: the way through
## stays fair (a way above the lava on every wall, the line holding once the
## exit is open, every raft sinking what the lava rose since the last) and rafts
## never come up in, or drift into, each other. The other Lava Rise tests:
## test_rooms_twists.gd.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const Lava := preload("res://sim/hazards/lava.gd")

const SUB := SimConfig.SUB


func test_rafts_rise_twice_as_fast_until_the_room_is_full_or_the_exit_shows() -> void:
	var sim := _started("lava", 18)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	l.draw_plan(SimRng.new(9))
	sim.room.points = 2
	l.on_bounce(sim, SimRng.new(1))
	assert_eq(l.rises, 2 * Lava.RAFT_PER_POINT, "two steps a point")
	sim.room.points = 100
	l.on_bounce(sim, SimRng.new(2))
	assert_eq(l.rises, Lava.FULL_RISES, "no cap: it fills the room")
	assert_true(l.line_at(l.rises) <= SimConfig.KILL_TOP, "over the ceiling's kill line")
	l.rises = 4
	l.counted = sim.room.points
	sim.state.exit_open = true
	sim.room.points += 2
	l.on_bounce(sim, SimRng.new(3))
	assert_eq(l.rises, 4, "no more rises once the exit is open")
	sim.state.exit_open = false
	sim.state.exit_preview = true
	sim.room.points += 2
	l.on_bounce(sim, SimRng.new(4))
	assert_eq(l.rises, 4, "nor once its ghost shows")


## However high the lava, the wall ahead keeps every slot still clear of it free.
func test_high_lava_keeps_the_slots_above_it_free() -> void:
	var sim := _started("lava", 19)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	for n in range(0, Lava.FULL_RISES + 1):
		l.rises = n
		l.counted = sim.room.points
		var edge := l.line_at(n)
		var mask: int = l.adjust_wall(sim, 1, all)
		var clear := 0
		var free := 0
		for slot in SimConfig.SLOT_COUNT:
			if l._slot_clear(slot, edge):
				clear += 1
				if not RoomRules.has_slot(mask, slot):
					free += 1
		assert_true(free >= mini(clear, Lava.RUN), "%d rises: a way above the lava" % n)


## The sink keeps up: a player who takes every raft as it comes keeps the lava
## within two points' rise of the floor all room long.
func test_taking_every_raft_keeps_the_lava_down() -> void:
	for seed_value in 8:
		var sim := _started("lava", 40 + seed_value)
		var l: Lava = sim.room.hazards[0]
		l.mode = Lava.Mode.RAFTS
		l.draw_plan(SimRng.new(seed_value))
		var most := 0
		for p in 30:
			sim.room.points += 1
			l.on_bounce(sim, SimRng.new(p))
			most = maxi(most, l.rises)
			for i in Lava.MAX_RAFTS:
				if l.raft_on[i]:
					l.raft_age[i] = Lava.RAFT_RISE
					l.line = l.line_at(l.rises)
					sim.state.x = l.raft_x[i]
					sim.state.y = l.line - Lava.RAFT_HIGH - SimConfig.BIRD_RADIUS + SUB
					sim.state.vy = 4 * SUB
					l.touch(sim)
		assert_true(
			most <= 2 * Lava.RAFT_PER_POINT, "seed %d: at most %d rises" % [seed_value, most]
		)


## Rafts never come up in each other, and never drift into each other.
func test_rafts_keep_apart() -> void:
	for seed_value in 64:
		var sim := _started("lava", 60 + seed_value)
		var l: Lava = sim.room.hazards[0]
		l.mode = Lava.Mode.RAFTS
		l.draw_plan(SimRng.new(seed_value))
		l.raft_points = sim.room.points
		sim.room.points += Lava.RAFT_TWO
		l.on_bounce(sim, SimRng.new(1))
		for i in seed_value * 5:
			l.step(sim)
		sim.room.points += Lava.RAFT_EVERY
		l.on_bounce(sim, SimRng.new(2))
		assert_true(l.raft_on[0] and l.raft_on[1], "two rafts")
		for i in 900:
			var d := absi(l.raft_x[1] - l.raft_x[0])
			assert_true(
				d >= Lava.RAFT_APART - 2 * Lava.RAFT_SPEED,
				"seed %d step %d apart" % [seed_value, i]
			)
			if d < Lava.RAFT_APART - 2 * Lava.RAFT_SPEED:
				return
			assert_true(
				l.raft_x[0] >= Lava.RAFT_X_MIN and l.raft_x[0] <= Lava.RAFT_X_MAX, "in range"
			)
			assert_true(
				l.raft_x[1] >= Lava.RAFT_X_MIN and l.raft_x[1] <= Lava.RAFT_X_MAX, "in range"
			)
			l.step(sim)


## Same seed, same rafts: the spot of the raft due at a point is drawn at room
## start, whatever the bird did before.
func test_raft_spots_are_drawn_at_room_start() -> void:
	var a := _started("lava", 21)
	var b := _started("lava", 21)
	var la: Lava = a.room.hazards[0]
	var lb: Lava = b.room.hazards[0]
	for l: Lava in [la, lb]:
		l.mode = Lava.Mode.RAFTS
		l.draw_plan(SimRng.new(77))
		l.raft_points = 0
	a.room.points = 4
	b.room.points = 4
	la.rises = 3
	lb.rises = 3
	la.on_bounce(a, SimRng.new(1))
	lb.on_bounce(b, SimRng.new(999))
	assert_eq(la.raft_x[0], lb.raft_x[0], "the same spot whatever the bounce draws")
	assert_eq(la.raft_x[0], la.plan_x[(4 / Lava.RAFT_EVERY) % Lava.RAFT_PLAN], "the planned spot")


static func _started(id: String, seed_value: int) -> GameSim:
	var sim := Rooms.sim_in_room(id, seed_value)
	sim.state.started = true
	return sim
