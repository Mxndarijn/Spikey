extends TestCase
## ArrivalAhead and ArrivalPlan: the portal arrival's check is worked
## out ahead on a worker thread, the portal tick takes it instead of playing the
## layouts itself (the hitch out of a portal: seconds on a phone), and the run
## is exactly the run without it.

## Portals compared (with a plan taken) before the run test stops.
const PORTALS := 3
const MAX_SEEDS := 16
const MAX_TICKS := 4000

## GameSim fields in ArrivalPlan.key, and those left out with why (a field added
## to GameSim must be put in one: tests below).
const KEYED := [
	"seed_value",
	"season",
	"practice_room",
	"forced_variant",
	"wall_run",
	"state",
	"_rng",
	"_spine",
	"_points_override",
	"_points_also",
	"_free_lo",
	"_free_hi",
]
const NOT_KEYED := [
	# Started again by RoomRuntime.start (its rng_seed is keyed).
	"room",
	# Cleared every step; the arrival's copies only append.
	"events",
	# False on the real sim; set by _arrival_retries before it reads them.
	"_checking",
	"_arrival_unpin",
	"_arrival_band",
	"_arrival_unfit",
	# The offers themselves, and tool info.
	"_arrival_offers",
	"_arrival_planned",
	# For a revive; copies never keep an entry.
	"_entry_room",
	"_entry_state",
	"_entry_rng",
	"_entry_spine",
]
## RoomRuntime.start sets every field again but these, which it reads: a field
## added there must be checked (and keyed in ArrivalPlan.key if start keeps it).
const ROOM_KEPT := ["rng_seed"]
const ROOM_FIELDS := [
	"def",
	"index",
	"t",
	"ticks",
	"points",
	"variant",
	"hazards",
	"tide_left",
	"tide_right",
	"tide_salt_left",
	"tide_salt_right",
	"blink_left",
	"blink_right",
	"gravity",
	"rng_seed",
	"walls",
	"entry_score",
]


static func _tap(sim: GameSim) -> bool:
	if not sim.state.started:
		return true
	return ArrivalCheck._toward(sim, ArrivalCheck.gap_target(sim))


func test_a_run_with_plans_ahead_is_the_same_run() -> void:
	var planned := 0
	var portals := 0
	for s in MAX_SEEDS:
		var seed_value := 9000 + s * 7919
		var plain := GameSim.new(seed_value)
		var ahead_sim := GameSim.new(seed_value)
		var ahead := ArrivalAhead.new()
		while not plain.is_over() and plain.state.tick < MAX_TICKS:
			var tap := _tap(plain)
			plain.step(tap)
			ahead.before_step(ahead_sim)
			ahead_sim.step(tap)
			ahead.after_step(ahead_sim)
			if plain.checksum() != ahead_sim.checksum():
				fail("seed %d: runs differ at tick %d" % [seed_value, plain.state.tick])
				ahead.stop()
				return
			if GameSim.Event.ROOM_CHANGE in plain.events:
				portals += 1
				assert_false(ArrivalPlan.taken(plain), "the plain run checks itself")
				if ArrivalPlan.taken(ahead_sim):
					planned += 1
		ahead.stop()
		if planned >= PORTALS:
			break
	assert_true(portals > 0, "the runs went through a portal")
	assert_true(
		planned >= mini(PORTALS, portals), "plans taken at %d of %d portals" % [planned, portals]
	)


func test_the_plan_is_the_check_the_portal_plays() -> void:
	var sim := _at_open_exit()
	if sim == null:
		fail("no run reached an open exit")
		return
	var s := sim.state
	var plan := ArrivalPlan.plan(SimCopy.copy(sim), s.exit_side, s.exit_a_kind, s.exit_a_y)
	var copy := SimCopy.copy(sim)
	var next := copy._through_door(s.exit_a_kind, s.exit_a_y)
	assert_eq(plan[0], ArrivalPlan.key(copy, s.exit_side, next), "the key")
	assert_eq(plan[1], copy._arrival_retries(s.exit_side, next), "the retries")
	assert_eq(
		[plan[2], plan[3], plan[4]],
		[copy._arrival_unpin, copy._arrival_band, copy._arrival_unfit],
		"the flags"
	)


func test_a_plan_with_another_key_is_not_taken() -> void:
	var sim := _at_open_exit()
	if sim == null:
		fail("no run reached an open exit")
		return
	var s := sim.state
	var plan := ArrivalPlan.plan(SimCopy.copy(sim), s.exit_side, s.exit_a_kind, s.exit_a_y)
	# A plan from another state (one coin more): the sim checks itself.
	var other := SimCopy.copy(sim)
	other.state.coins += 1
	var wrong := ArrivalPlan.plan(other, s.exit_side, s.exit_a_kind, s.exit_a_y)
	assert_ne(wrong[0], plan[0], "another state, another key")
	var copy := SimCopy.copy(sim)
	var next := copy._through_door(s.exit_a_kind, s.exit_a_y)
	ArrivalPlan.offer(copy, [wrong])
	copy._arrival_retries(s.exit_side, next)
	assert_false(ArrivalPlan.taken(copy), "a stale plan is dropped")
	var right := SimCopy.copy(sim)
	next = right._through_door(s.exit_a_kind, s.exit_a_y)
	ArrivalPlan.offer(right, [wrong, plan])
	assert_eq(right._arrival_retries(s.exit_side, next), plan[1])
	assert_true(ArrivalPlan.taken(right), "its own plan is taken")


func test_every_game_sim_field_is_keyed_or_left_out_on_purpose() -> void:
	for p in (GameSim as Script).get_script_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		assert_true(
			p.name in KEYED or p.name in NOT_KEYED,
			"GameSim.%s: in ArrivalPlan.key or not? (see KEYED)" % p.name
		)


func test_room_start_sets_every_field_it_does_not_read() -> void:
	var names: Array = []
	for p in (RoomRuntime as Script).get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(p.name)
	assert_eq(names, ROOM_FIELDS, "RoomRuntime fields changed: does start() set each again?")
	for name: String in ROOM_KEPT:
		assert_true(name in ROOM_FIELDS)


## A run (the simple player) on the tick an exit opened, or null.
static func _at_open_exit() -> GameSim:
	for s in MAX_SEEDS:
		var sim := GameSim.new(9000 + s * 7919)
		while not sim.is_over() and sim.state.tick < MAX_TICKS:
			sim.step(_tap(sim))
			if GameSim.Event.EXIT_OPEN in sim.events:
				return sim
	return null
