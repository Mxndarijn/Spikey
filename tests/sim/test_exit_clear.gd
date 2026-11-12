extends TestCase
## Nothing kills in a room's exit mouths, from the room's start (its exits
## are planned then, on both walls: sim/exit_zone.gd): balls
## bounce off it, sliders stop at it, shots, drops and sparks break on it,
## pistons sit their cycle out and beams stop short, and ExitPlanner never
## puts an exit where a hazard is already. The full sweep (SurvivalSearch
## through every variant, and full runs in every season, seed 4206176851
## among them) runs on FastSim: `tools/fastsim.ps1 -Mode check -Check exits`,
## part of tools/check.ps1. Here: every variant with the bird held still, on
## a coarse probe.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const Beam := preload("res://sim/hazards/beam.gd")
const Bouncer := preload("res://sim/hazards/bouncer.gd")
const Stalker := preload("res://sim/hazards/stalker.gd")

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


## A practice room of `index` in variant `variant`, its exits planned (both
## walls), with the bird held mid-room at the right wall's exit height (so a
## Stalker is drawn to it).
static func practice(index: int, variant: String, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)
	sim.state.x = SimConfig.WORLD_W / 2
	sim.state.vx = SimConfig.SPEED_X
	sim.state.y = sim.state.plan_a_y_right
	return sim


## No planned exits, so a test can put one exit where it wants.
static func clear_plan(sim: GameSim) -> void:
	sim.state.plan_a_y_left = 0
	sim.state.plan_b_y_left = 0
	sim.state.plan_a_y_right = 0
	sim.state.plan_b_y_right = 0


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
				var sim := practice(index, variant, 1000 + index * 7 + k)
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
						% [
							all[index].id,
							variant,
							1000 + index * 7 + k,
							sim.room.t,
							", ".join(found)
						]
					)
				)


## A live beam across an exit's row stops at the mouth, and only there.
func test_a_beam_stops_short_of_the_mouth() -> void:
	var index := RoomCatalog.index_of("beams")
	var sim := GameSim.new(5, RoomCatalog.all()[index].season, index)
	var beam: Beam = sim.room.hazards[0]
	clear_plan(sim)
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
	clear_plan(sim)
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
	clear_plan(sim)
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
