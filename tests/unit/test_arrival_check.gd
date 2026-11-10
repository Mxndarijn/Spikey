extends TestCase
## Out of a portal the room is laid out for a player who is slow to react
## (GameSim._arrival_retries, ArrivalCheck).

const Rotor := preload("res://sim/hazards/rotor.gd")


static func _sim_at(score: int, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.step(true)
	sim.state.score = score
	return sim


## Out of a portal the room is laid out so a bird that only holds its height
## for ARRIVAL_BLIND ticks (a player still reading the room) can live on.
func test_a_slow_reaction_out_of_a_portal_is_fair() -> void:
	var fair := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW
	var ok := 0
	var count := 0
	for id: String in ["isles", "pinwheel", "swing", "stalac", "gates"]:
		var index := RoomCatalog.index_of(id)
		for i in 8:
			var sim := _sim_at(maxi(RoomCatalog.all()[index].from_score, 20), 300 + i)
			sim.state.y = (160 + (i * 53) % 320) * SimConfig.SUB
			var side := i % 2
			for k in sim._arrival_retries(side, index):
				sim._rng.next_u32()
			sim._arrive_in(side, index)
			count += 1
			if ArrivalCheck.score(SimClone.copy(sim)) >= fair:
				ok += 1
	assert_true(ok * 10 >= count * 9, "fair arrivals: %d/%d" % [ok, count])


func test_arrival_checks_leave_the_run_untouched_and_never_nest() -> void:
	var sim := _sim_at(20, 7)
	var before := sim.checksum()
	sim._arrival_retries(0, RoomCatalog.index_of("isles"))
	assert_eq(sim.checksum(), before, "the check plays on copies only")
	var c := SimClone.copy(sim)
	c._checking = true
	assert_eq(c._arrival_retries(0, RoomCatalog.index_of("isles")), 0, "no check in a check")


## Out of a portal Pinwheel sits off the bird's height: a bird that holds its
## height (hopping up about HOP) clears every blade.
func test_pinwheel_moves_off_the_arriving_bird() -> void:
	var index := RoomCatalog.index_of("pinwheel")
	var reach: int = Rotor.BLADE_LENGTH + Rotor.BLADE_HALF_W + SimConfig.BIRD_RADIUS
	for i in 12:
		var sim := _sim_at(40, 500 + i)
		sim.state.y = (200 + i * 25) * SimConfig.SUB
		sim._arrive_in(i % 2, index)
		var r: Hazard = sim.room.hazards[0]
		var below: int = r.center_y - sim.state.y
		assert_true(below >= reach or -below >= reach + Rotor.HOP, "clear at %d" % i)
		assert_between(r.center_y, 140 * SimConfig.SUB, 500 * SimConfig.SUB)
	var start := GameSim.new(3)
	start._enter_room(index)
	assert_eq(start.room.hazards[0].center_y, Rotor.CENTER_Y, "in the middle at a run's start")
