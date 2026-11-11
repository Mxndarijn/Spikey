class_name BotSetups
extends RefCounted
## The sims the FastSim bot checks (tools/fastsim/Checks.cs) start from, the
## GDScript originals of their C# copies. tools/fastsim_parity.gd records runs
## from each of them, so the parity step proves the C# copies build the same
## sims. Test/tool code only.

## Heights a revived bird can have come in at (Checks.cs Revive).
const ENTRY_YS: Array[int] = [140 * SimConfig.SUB, 300 * SimConfig.SUB, 480 * SimConfig.SUB]


## Brings a real run's bird into room `index` through a portal at height `y`,
## flying toward wall `toward`, laid out as GameSim._go_through does (the
## arrival check's retries). A revive restarts the room from here.
static func came_in(sim: GameSim, index: int, toward: int, y: int) -> void:
	sim.state.y = y
	for i in sim._arrival_retries(toward, index):
		sim._rng.next_u32()
	sim._arrive_in(toward, index)


## A real run that came into room `index` toward wall `toward` at height `y`,
## at a score that fits `exit` ("none", "open" or "ghost" on wall `side`),
## killed there and revived. (Checks.cs Revive)
static func revived(
	index: int, seed_value: int, exit: String, side: int, toward: int, y: int
) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	sim.state.score = base + 3
	came_in(sim, index, toward, y)
	match exit:
		"open":
			sim.state.score = base
			ExitPlanner.plan(sim, sim._rng, side, base)
			sim.state.exit_open = true
		"ghost":
			sim.state.score = base + every - 1
			ExitPlanner.plan(sim, sim._rng, side, base + every)
			sim.state.exit_preview = true
	sim.kill(SimState.DeathCause.FLOOR)
	sim.revive()
	return sim


## A real run that came into room `index` (toward wall `seed_value % 2`) with
## an exit ("open" or "ghost") on wall `side` at height `y`, killed there and
## revived. (Checks.cs Crawl)
static func crawl_revived(index: int, seed_value: int, exit: String, side: int, y: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	# Not a fork score, so there is one exit.
	var base := 60
	sim.state.score = base + 3
	came_in(sim, index, seed_value % 2, sim.state.y)
	if exit == "open":
		sim.state.score = base
		ExitPlanner.plan(sim, sim._rng, side, base)
		sim.state.exit_open = true
	else:
		sim.state.score = base + SimConfig.POINTS_PER_ROOM - 1
		ExitPlanner.plan(sim, sim._rng, side, base + SimConfig.POINTS_PER_ROOM)
		sim.state.exit_preview = true
	sim.state.exit_a_y = y
	sim.kill(SimState.DeathCause.FLOOR)
	sim.revive()
	return sim


## A real run that came into the gates room (toward wall `seed_value % 2`) with
## an exit at `exit_y` on wall `side`, open or planned (a ghost), killed and
## revived. (Checks.cs Gates)
static func gates_revived(
	seed_value: int, open: bool, side: int, exit_y: int, variant: String = "classic"
) -> GameSim:
	var index := RoomCatalog.index_of("gates")
	var def: RoomDef = RoomCatalog.all()[index]
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	var sim := GameSim.new(seed_value, def.season, -1, variant)
	sim.step(true)
	sim.state.score = base if open else base + every - 1
	came_in(sim, index, seed_value % 2, sim.state.y)
	ExitPlanner.plan(sim, sim._rng, side, base if open else base + every)
	sim.state.exit_a_y = exit_y
	sim.state.exit_open = open
	sim.state.exit_preview = not open
	sim.kill(SimState.DeathCause.HAZARD)
	sim.revive()
	return sim


## Practice room `id` as `variant`.
static func practice(id: String, seed_value: int, variant: String = "classic") -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	return GameSim.new(seed_value, def.season, index, variant)


## A real run that came into room `id` (toward wall `seed_value % 2`) with an
## exit ("open" or "ghost") on wall `side`, killed there and revived.
## (Checks.cs Isles)
static func isles_revived(
	id: String, seed_value: int, exit: String, side: int, variant: String = "classic"
) -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season, -1, variant)
	sim.step(true)
	var every := SimConfig.POINTS_PER_ROOM
	var base := maxi(every, (def.from_score + every - 1) / every * every)
	if exit == "open":
		sim.state.score = base
		came_in(sim, index, seed_value % 2, sim.state.y)
		ExitPlanner.plan(sim, sim._rng, side, base)
		sim.state.exit_open = true
	else:
		sim.state.score = base + every - 1
		came_in(sim, index, seed_value % 2, sim.state.y)
		ExitPlanner.plan(sim, sim._rng, side, base + every)
		sim.state.exit_preview = true
	sim.kill(SimState.DeathCause.HAZARD)
	sim.revive()
	return sim
