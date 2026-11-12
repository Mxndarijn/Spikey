extends TestCase
## Nothing kills in a room's exit mouth once the exit is drawn (a ghost or
## open: sim/exit_zone.gd), and whatever was there gets out at once: balls
## bounce off it, sliders stop at it, shots, drops and sparks break on it,
## pistons sit their cycle out and beams stop short, and ExitPlanner never
## puts an exit where a hazard is already. The full sweep (SurvivalSearch
## through every variant, and full runs in every season, seed 4206176851
## among them) runs on FastSim-RS: `tools/fastsim.ps1 -Mode check -Check exits`
## (tools/fastsim-rs/fastsim/src/checks/exits.rs), part of tools/check.ps1.
## Here: every variant with the bird held still, on a coarse probe.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const Beam := preload("res://sim/hazards/beam.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const Stalker := preload("res://sim/hazards/stalker.gd")
const Piston := preload("res://sim/hazards/piston.gd")

## Steps each room plays with its exit open, probing every PROBE_EVERY.
const STEPS := 240
const PROBE_EVERY := 3


## The kinds of hazard that kill a bird in one of the room's exit mouths now:
## bird circles from touching the wall to a bird radius back, within EXIT_HALF.
static func blockers(sim: GameSim) -> Array[String]:
	var out: Array[String] = []
	var s := sim.state
	var r := SimConfig.BIRD_RADIUS
	var keep_x := s.x
	var keep_y := s.y
	for i in ExitZone.BOXES:
		if ExitZone.box_y(sim, i) == 0:
			continue
		var side := ExitZone.box_side(sim, i)
		var wall := sim.room.wall_left() + r if side == 0 else sim.room.wall_right() - r
		var dir := 1 if side == 0 else -1
		for dx: int in [0, r - 1]:
			var dy := -SimConfig.EXIT_HALF
			while dy <= SimConfig.EXIT_HALF:
				s.x = wall + dir * dx
				s.y = ExitZone.box_y(sim, i) + dy
				for h in sim.room.hazards:
					if h.alive and h.kills(sim) and not out.has(h.kind):
						out.append(h.kind)
				dy += 8 * SimConfig.SUB
	s.x = keep_x
	s.y = keep_y
	return out


## A practice room of `index` in variant `variant`, played `steps` steps
## with no exit drawn, then its planned exit on wall `side` drawn as a ghost
## (as at a bounce), with the bird held mid-room at its height (so a Stalker
## is drawn to it).
static func drawn_late(
	index: int, variant: String, seed_value: int, side: int, steps: int
) -> GameSim:
	var sim := GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)
	sim.state.x = SimConfig.WORLD_W / 2
	sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	for i in steps:
		sim.room.step(sim)
	ExitPlanner.use_plan(sim, side, sim.state.plan_at)
	sim.state.exit_preview = true
	sim.state.y = sim.state.exit_a_y
	return sim


func test_no_hazard_in_an_exit_mouth() -> void:
	var all := RoomCatalog.all()
	for index in all.size():
		var ids: Array[String] = [""]
		if not all[index].variants.is_empty():
			ids.clear()
			for v in all[index].variants:
				ids.append(v.id)
		for variant in ids:
			for k in 2:
				# Drawn early and late, on each wall: whatever is in the mouth
				# when it is drawn gets out on the next step.
				var seed_value := 1000 + index * 7 + k
				var sim := drawn_late(index, variant, seed_value, k, 20 + seed_value % 7 * 60)
				sim.room.step(sim)
				var found: Array[String] = []
				for step in STEPS:
					sim.room.step(sim)
					if step % PROBE_EVERY == 0:
						found = blockers(sim)
						if not found.is_empty():
							break
				assert_true(
					found.is_empty(),
					(
						"%s/%s seed %d, step %d: %s in an exit's mouth"
						% [all[index].id, variant, seed_value, sim.room.t, ", ".join(found)]
					)
				)


## A live beam across an exit's row stops at the mouth, and only there.
func test_a_beam_stops_short_of_the_mouth() -> void:
	var index := RoomCatalog.index_of("beams")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index)
	var beam: Beam = sim.room.hazards[0]
	sim.state.exit_side = 1
	sim.state.exit_open = true
	sim.state.exit_a_y = beam.rows[0]
	assert_eq(beam.beam_right(sim, 0), ExitZone.left_on(sim, 1) - 1)
	assert_eq(beam.beam_left(sim, 0), sim.room.wall_left())
	sim.state.exit_a_y = beam.rows[0] + ExitZone.HALF + Beam.HALF_H + SimConfig.SUB
	assert_eq(beam.beam_right(sim, 0), sim.room.wall_right(), "a beam clear of the mouth")


## A ball flying at the mouth bounces off its face, as off the wall.
func test_a_ball_bounces_off_the_mouth() -> void:
	var index := RoomCatalog.index_of("bramble")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index, "classic")
	sim.state.exit_side = 1
	sim.state.exit_open = true
	sim.state.exit_a_y = 320 * SimConfig.SUB
	var ball := Bouncer.new()
	ball.x = ExitZone.left_on(sim, 1) - ball.radius - 2 * SimConfig.SUB
	ball.y = sim.state.exit_a_y
	ball.vx = Bouncer.SPEED_X
	ball.vy = 0
	for i in 4:
		ball.move(sim)
	assert_true(ball.vx < 0, "turned back")
	assert_true(ball.x + ball.radius < ExitZone.left_on(sim, 1), "outside the mouth")


## The Stalker's spikes slide up to the mouth's edge and wait there.
func test_the_stalker_waits_at_the_mouth() -> void:
	var index := RoomCatalog.index_of("stalker")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index)
	sim.state.vx = SimConfig.SPEED_X
	sim.state.exit_side = 1
	sim.state.exit_open = true
	sim.state.exit_a_y = 320 * SimConfig.SUB
	sim.state.y = sim.state.exit_a_y
	var stalker: Stalker = sim.room.hazards[0]
	stalker.y = Stalker.MIN_Y
	for i in 600:
		stalker.step(sim)
	var gap := absi(stalker.y - sim.state.exit_a_y)
	assert_eq(gap, ExitZone.HALF + Stalker.HALF_H + 1, "waits right at the edge")


## Before its exit is drawn, the planned spot is no wall to anything: a ball
## flies into it as into any other part of the room.
func test_an_exit_not_yet_drawn_stops_nothing() -> void:
	var index := RoomCatalog.index_of("bramble")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index, "classic")
	assert_true(sim.state.plan_a_y_right > 0, "the exit is planned")
	assert_false(sim.state.exit_open or sim.state.exit_preview, "but not drawn")
	var ball := Bouncer.new()
	ball.x = ExitZone.left_on(sim, 1) - ball.radius - 2 * SimConfig.SUB
	ball.y = sim.state.plan_a_y_right
	ball.vx = Bouncer.SPEED_X
	ball.vy = 0
	for i in 4:
		ball.move(sim)
	assert_true(ball.vx > 0, "flies on")
	assert_true(ball.x + ball.radius > ExitZone.left_on(sim, 1), "into the planned spot")


## Drawn while a ball sits in its mouth, the exit bounces it out at once.
func test_a_ball_in_the_mouth_when_it_is_drawn_gets_out() -> void:
	var index := RoomCatalog.index_of("bramble")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index, "classic")
	var ball := Bouncer.new()
	ball.x = ExitZone.left_on(sim, 1) + ExitZone.DEPTH / 2
	ball.y = sim.state.plan_a_y_right
	ball.vx = Bouncer.SPEED_X
	ball.vy = 0
	ExitPlanner.use_plan(sim, 1, sim.state.plan_at)
	sim.state.exit_preview = true
	ball.move(sim)
	assert_true(ball.vx < 0, "turned back")
	assert_false(ExitZone.hits_circle(sim, ball.x, ball.y, ball.radius), "out of the mouth")


## Drawn while the Stalker's spikes sit in its mouth, they jump clear at once.
func test_a_stalker_in_the_mouth_when_it_is_drawn_jumps_clear() -> void:
	var index := RoomCatalog.index_of("stalker")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index)
	sim.state.vx = SimConfig.SPEED_X
	var stalker: Stalker = sim.room.hazards[0]
	sim.state.y = sim.state.plan_a_y_right
	stalker.y = sim.state.y
	stalker.step(sim)
	assert_eq(stalker.y, sim.state.y, "undrawn: it sits on the planned spot")
	ExitPlanner.use_plan(sim, 1, sim.state.plan_at)
	sim.state.exit_preview = true
	stalker.step(sim)
	var gap := absi(stalker.y - sim.state.exit_a_y)
	assert_true(gap > ExitZone.HALF + Stalker.HALF_H, "clear of the mouth")


## Drawn while a ram is out across its mouth, the ram is back in the wall on
## the next step, and sits that cycle out.
func test_a_ram_out_in_the_mouth_when_it_is_drawn_pulls_back() -> void:
	var index := RoomCatalog.index_of("piston")
	var sim := GameSim.new(3, RoomCatalog.all()[index].season, index, "classic")
	var p: Piston = null
	for h in sim.room.hazards:
		if h is Piston and (h as Piston).side == 1:
			p = h
	if p == null:
		p = sim.room.hazards[0]
	while p.state() != Piston.State.HOLD:
		sim.room.step(sim)
	sim.state.exit_side = p.side
	sim.state.exit_a_y = p.y
	sim.state.exit_a_kind = SimState.ExitKind.NORMAL
	sim.state.exit_b_kind = SimState.ExitKind.NORMAL
	sim.state.exit_preview = true
	sim.room.step(sim)
	assert_eq(p.state(), Piston.State.IDLE, "back in the wall")
	assert_eq(p.extent(), 0)
