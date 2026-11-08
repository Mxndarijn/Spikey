extends SceneTree
## Headless playtest with PlannerBot (a strong lookahead player).
##   godot --headless --path . -s res://tools/playtest.gd -- <mode> <out.json> [seeds] [filter]
##     [first]
## `first` skips that many seeds, so parallel copies can each take a slice
## (tools/sweep.ps1 does this).
## mode "rooms": practice every room kind from its first score, several seeds;
##               reports points per room, deaths and what killed the bird.
## mode "runs":  full real runs through the portals; reports scores, rooms
##               reached and deaths soon after entering a room.
## mode "search": SurvivalSearch per room: can anyone survive SEARCH_TICKS there?
##               (a sixth argument sets another length in ticks)
## mode "searchruns": SurvivalSearch over full runs through the portals (the
##               fourth argument is the run length in ticks).

const ROOM_TICKS := 3600
const ROOM_POINTS := 25
const RUN_TICKS := 9000
## A death this soon after entering a room counts as a transition death.
const ARRIVAL_TICKS := 90
## How long the search must survive in each room (about 18 points).
const SEARCH_TICKS := 1500
## How long the search plays a full run (about 70 points).
const SEARCH_RUN_TICKS := 6000

## Seeds to skip (see the usage line).
var _first := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "rooms"
	var out := args[1] if args.size() > 1 else "user://playtest.json"
	var seeds := int(args[2]) if args.size() > 2 else 4
	# "*" (or nothing) means every room.
	var filter := args[3] if args.size() > 3 and args[3] != "*" else ""
	_first = int(args[4]) if args.size() > 4 else 0
	var ticks := int(args[5]) if args.size() > 5 and int(args[5]) > 0 else SEARCH_TICKS
	var start := Time.get_ticks_msec()
	var report: Dictionary
	match mode:
		"rooms":
			report = _rooms(seeds, filter)
		"search":
			report = _search_rooms(seeds, filter, ticks)
		"searchruns":
			report = _search_runs(seeds, int(filter) if filter.is_valid_int() else SEARCH_RUN_TICKS)
		_:
			report = _runs(seeds)
	report.seconds = (Time.get_ticks_msec() - start) / 1000.0
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("playtest %s done in %.0f s -> %s" % [mode, report.seconds, out])
	quit(0)


func _rooms(seeds: int, filter: String) -> Dictionary:
	var rooms := []
	for def in RoomCatalog.all():
		if not filter.is_empty() and not def.id.contains(filter):
			continue
		var index := RoomCatalog.index_of(def.id)
		var runs := []
		for s in seeds:
			runs.append(_play_room(index, def, 1000 + (_first + s) * 77))
		rooms.append({"id": def.id, "group": def.group, "from": def.from_score, "runs": runs})
		var pts := 0
		for r: Dictionary in runs:
			pts += int(r.points)
		print("  %-11s avg points %5.1f" % [def.id, float(pts) / seeds])
	return {"mode": "rooms", "seeds": seeds, "rooms": rooms}


func _play_room(index: int, def: RoomDef, seed_value: int) -> Dictionary:
	var season := def.season if def.season != Seasons.NONE else Seasons.NONE
	var sim := GameSim.new(seed_value, season, index)
	var bot := PlannerBot.new(seed_value)
	var start_score := sim.state.score
	var since_room := 0
	var deaths_after_exit := 0
	while not sim.is_over() and sim.state.tick < ROOM_TICKS:
		sim.step(bot.decide(sim))
		since_room += 1
		if GameSim.Event.ROOM_CHANGE in sim.events:
			since_room = 0
		if sim.state.score - start_score >= ROOM_POINTS:
			break
	var dead := sim.is_over()
	return {
		"seed": seed_value,
		"points": sim.state.score - start_score,
		"ticks": sim.state.tick,
		"dead": dead,
		"cause": SimState.DeathCause.keys()[sim.state.death_cause] if dead else "",
		"after_exit": dead and since_room < ARRIVAL_TICKS and sim.state.room_index > 0,
		"y": sim.state.y / SimConfig.SUB,
		"x": sim.state.x / SimConfig.SUB,
	}


func _runs(seeds: int) -> Dictionary:
	var runs := []
	for s in seeds:
		var seed_value := 5000 + (_first + s) * 131
		var sim := GameSim.new(seed_value)
		var bot := PlannerBot.new(seed_value)
		var rooms := ["open"]
		var since_room := 0
		var forks := 0
		while not sim.is_over() and sim.state.tick < RUN_TICKS:
			sim.step(bot.decide(sim))
			since_room += 1
			if GameSim.Event.EXIT_OPEN in sim.events and sim.state.exit_b_kind != 0:
				forks += 1
			if GameSim.Event.ROOM_CHANGE in sim.events:
				since_room = 0
				rooms.append(RoomCatalog.all()[sim.state.room_kind].id)
		var dead := sim.is_over()
		var run := {
			"seed": seed_value,
			"score": sim.state.score,
			"coins": sim.state.coins,
			"ticks": sim.state.tick,
			"rooms": rooms,
			"forks": forks,
			"route": sim.state.route,
			"dead": dead,
			"cause": SimState.DeathCause.keys()[sim.state.death_cause] if dead else "",
			"died_in": rooms[rooms.size() - 1],
			"arrival_death": dead and since_room < ARRIVAL_TICKS and rooms.size() > 1,
			"ticks_in_room": since_room,
		}
		runs.append(run)
		print(
			(
				"  run %d: score %d, rooms %d, died in %s (%s) after %d ticks there"
				% [s, run.score, rooms.size(), run.died_in, run.cause, since_room]
			)
		)
	return {"mode": "runs", "runs": runs}


func _search_rooms(seeds: int, filter: String, ticks: int) -> Dictionary:
	var rooms := []
	for def in RoomCatalog.all():
		if not filter.is_empty() and not def.id.contains(filter):
			continue
		var index := RoomCatalog.index_of(def.id)
		var runs := []
		var fails := 0
		for s in seeds:
			var seed_value := 1000 + (_first + s) * 77
			var sim := GameSim.new(seed_value, def.season, index)
			var search := SurvivalSearch.new()
			var ok := search.run(sim, ticks)
			if not ok:
				fails += 1
			(
				runs
				. append(
					{
						"seed": seed_value,
						"ok": ok,
						"ticks": search.ticks_survived,
						"width": search.peak_width,
						"level": search.level,
						"points": search.best.state.score - sim.state.score if ok else 0,
					}
				)
			)
		rooms.append({"id": def.id, "group": def.group, "from": def.from_score, "runs": runs})
		print("  %-11s impossible %d / %d" % [def.id, fails, seeds])
	return {"mode": "search", "seeds": seeds, "ticks": ticks, "rooms": rooms}


func _search_runs(seeds: int, ticks: int) -> Dictionary:
	var runs := []
	for s in seeds:
		var seed_value := 5000 + (_first + s) * 131
		var sim := GameSim.new(seed_value)
		var search := SurvivalSearch.new()
		var ok := search.run(sim, ticks)
		var run := {"seed": seed_value, "ok": ok, "ticks": search.ticks_survived}
		if ok:
			# Replay the winning taps to list the rooms on the way.
			var rooms := ["open"]
			var replay := GameSim.new(seed_value)
			for tap in search.best_inputs:
				replay.step(tap == 1)
				if GameSim.Event.ROOM_CHANGE in replay.events:
					rooms.append(RoomCatalog.all()[replay.state.room_kind].id)
			run.rooms = rooms
			run.score = replay.state.score
		else:
			var ids := []
			for k in search.last_rooms:
				ids.append(RoomCatalog.all()[k].id)
			run.died_in = ids
			run.deaths = search.last_deaths
		runs.append(run)
		print("  run %d: %s" % [s, JSON.stringify(run)])
	return {"mode": "searchruns", "runs": runs}
