extends SceneTree
## How long the sim takes to go through a portal into each room: the arrival
## check (GameSim._arrival_retries: layouts tried on copies) and the room start
## (GameSim._arrive_in: hazards, generated variants, exits planned). For every
## room kind, `seeds` seeds and a spread of exit heights. Prints each room's
## worst and mean, worst first.
##   godot --headless --path . -s res://tools/portal_timing.gd -- [seeds] [room]

const HEIGHTS := 5


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "runs":
		_runs(
			int(args[1]) if args.size() > 1 else 20, int(args[2]) if args.size() > 2 else 0, false
		)
		quit(0)
		return
	if args.size() > 0 and args[0] == "ahead":
		_runs(int(args[1]) if args.size() > 1 else 20, int(args[2]) if args.size() > 2 else 0, true)
		quit(0)
		return
	if args.size() > 0 and args[0] == "replays":
		_replays(args[1] if args.size() > 1 else "res://tests/replay/golden")
		quit(0)
		return
	var seeds := int(args[0]) if args.size() > 0 else 4
	var only := args[1] if args.size() > 1 else ""
	var rows: Array = []
	var all := RoomCatalog.all()
	for index in all.size():
		var def: RoomDef = all[index]
		if only != "" and def.id != only:
			continue
		var worst := 0
		var worst_check := 0
		var total := 0
		var n := 0
		var worst_case := ""
		for s in seeds:
			for hi in HEIGHTS:
				var sim := arrival_sim(def, 7000 + s * 977 + index * 31, hi)
				var t0 := Time.get_ticks_usec()
				var retries := sim._arrival_retries(SimConfig.EXIT_WALL, index)
				for i in retries:
					sim._rng.next_u32()
				var t1 := Time.get_ticks_usec()
				sim._arrive_in(SimConfig.EXIT_WALL, index)
				var t2 := Time.get_ticks_usec()
				var dt := t2 - t0
				total += dt
				n += 1
				if dt > worst:
					worst = dt
					worst_check = t1 - t0
					worst_case = (
						"seed %d h%d retries %d v%d"
						% [7000 + s * 977 + index * 31, hi, retries, sim.room.variant]
					)
		rows.append([worst, total / maxi(1, n), worst_check, def.id, worst_case])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("room          worst ms  (check ms)  mean ms   worst case")
	for r: Array in rows:
		print(
			(
				"%-12s %8.1f  (%8.1f)  %7.1f   %s"
				% [r[3], r[0] / 1000.0, r[2] / 1000.0, r[1] / 1000.0, r[4]]
			)
		)
	quit(0)


## Full runs with a quick simple player (ArrivalCheck's gap aim, never a
## lookahead), `seeds` seeds from `first`: every portal step's time, and the
## steps between portals for comparison. One line per portal: ms, room, score.
## `ahead` (mode "ahead"): with ArrivalAhead, as the game plays. Each job is
## waited for at once (headless runs faster than 60 Hz), and its time printed
## against the crossing it has in the game (about 1.4 s); the portal step's own
## time is then what the main thread still does.
func _runs(seeds: int, first: int, ahead: bool) -> void:
	var other := 0
	var job := 0
	for s in range(first, first + seeds):
		var sim := GameSim.new(9000 + s * 7919)
		var arrival := ArrivalAhead.new()
		while not sim.is_over() and sim.state.tick < 20000:
			var tap := false
			if sim.state.started:
				tap = ArrivalCheck._toward(sim, ArrivalCheck.gap_target(sim))
			else:
				tap = true
			var t0 := Time.get_ticks_usec()
			sim.step(tap)
			var dt := Time.get_ticks_usec() - t0
			if ahead:
				arrival.after_step(sim)
				if arrival.busy():
					var j0 := Time.get_ticks_usec()
					arrival.finish(sim)
					job = maxi(job, Time.get_ticks_usec() - j0)
					print("job    %8.1f ms" % [(Time.get_ticks_usec() - j0) / 1000.0])
			if GameSim.Event.ROOM_CHANGE in sim.events:
				var def: RoomDef = RoomCatalog.all()[sim.state.room_kind]
				print(
					(
						"portal %8.1f ms  %-12s score %d%s"
						% [
							dt / 1000.0,
							def.id,
							sim.state.score,
							"  planned" if ArrivalPlan.taken(sim) else ""
						]
					)
				)
			else:
				other = maxi(other, dt)
		arrival.stop()
	print("other steps max %.1f ms, longest job %.1f ms" % [other / 1000.0, job / 1000.0])


## Plays every replay (.json) in `dir` and prints how long each portal step took.
func _replays(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var r := Replay.from_dict(
			JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		)
		var sim := GameSim.new(r.seed_value, r.season)
		var next := 0
		var next_revive := 0
		var other := 0
		while sim.state.tick < r.end_tick:
			if sim.is_over():
				if next_revive >= r.revive_ticks.size() or not sim.revive():
					break
				next_revive += 1
			var tap := next < r.taps.size() and r.taps[next] == sim.state.tick
			if tap:
				next += 1
			var t0 := Time.get_ticks_usec()
			sim.step(tap)
			var dt := Time.get_ticks_usec() - t0
			if GameSim.Event.ROOM_CHANGE in sim.events:
				var def: RoomDef = RoomCatalog.all()[sim.state.room_kind]
				print(
					(
						"%s tick %5d  %-10s v%d  %8.1f ms"
						% [f, sim.state.tick, def.id, sim.room.variant, dt / 1000.0]
					)
				)
			else:
				other = maxi(other, dt)
		print("%s other steps max %.1f ms" % [f, other / 1000.0])


## A run about to go through the exit into room `def`: the score at an exit
## from the room's own first score on, the next room's seed drawn, the exit at
## height step `hi` of HEIGHTS.
static func arrival_sim(def: RoomDef, seed_value: int, hi: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	var s := sim.state
	s.started = true
	var per := SimConfig.POINTS_PER_ROOM
	s.score = maxi(per, (def.from_score + per - 1) / per * per)
	s.room_index = s.score / per
	var top := SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE
	var bottom := SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	s.anchor_y = top + (bottom - top) * hi / (HEIGHTS - 1)
	s.y = s.anchor_y
	s.x = SimConfig.WORLD_W - SimConfig.BIRD_RADIUS
	s.vx = SimConfig.SPEED_X
	sim._seed_room()
	return sim
