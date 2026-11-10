extends SceneTree
## Records runs for the FastSim parity check (tools/fastsim, the C# copy of
## sim/ for fast bots). The C# side replays every run and must get the same
## checksum on every tick.
##   godot --headless --path . -s res://tools/fastsim_parity.gd -- <out.txt> [quick]
##
## Cases, one per line:
##   run <name> <seed> <season> <practice> <actions> <checksums>
##     actions: 0 wait, 1 tap, r revive (between steps, no tick); one
##     checksum (GameSim.checksum()) after each action, comma separated.
##   search <name> <seed> <season> <practice> <ticks> <ok> <survived> <taps>
##     SurvivalSearch from a fresh sim; the C# search must find the same taps.
## Coverage: every room in practice (a gap-seeking bot and a SurvivalSearch
## line, so the bird lives long enough to see exits and portals), and full runs
## through the portals in every season, with a revive.

const AIM_TICKS := 600
const ROOM_SEARCH_TICKS := 700
const RUN_SEARCH_TICKS := 4000
const RUN_SEEDS := 3

var _lines := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://fastsim_parity.txt"
	var quick := args.size() > 1 and args[1] == "quick"
	var start := Time.get_ticks_msec()
	var rooms := RoomCatalog.all()
	for index in rooms.size():
		var def: RoomDef = rooms[index]
		for s in 2:
			var seed_value := 300 + index * 17 + s
			_aim_case("aim_" + def.id, seed_value, def.season, index, AIM_TICKS)
		if not quick:
			_search_case("search_" + def.id, 900 + index, def.season, index, ROOM_SEARCH_TICKS)
	var seeds := 1 if quick else RUN_SEEDS
	for s in seeds:
		for season in range(Seasons.NONE, Seasons.COUNT):
			var seed_value := 7000 + s * 101 + (season + 1) * 7
			_aim_case("aimrun", seed_value, season, -1, AIM_TICKS * 3)
			if not quick:
				_search_case("searchrun", seed_value, season, -1, RUN_SEARCH_TICKS)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print(
		(
			"fastsim parity: %d cases in %.0f s -> %s"
			% [_lines.size(), (Time.get_ticks_msec() - start) / 1000.0, out]
		)
	)
	quit(0)


## A gap-seeking bot (PlannerBot.aim) with a revive when it dies in a real run.
func _aim_case(name: String, seed_value: int, season: int, practice: int, ticks: int) -> void:
	var sim := GameSim.new(seed_value, season, practice)
	var rng := SimRng.new(seed_value)
	var actions := ""
	var sums := PackedStringArray()
	for t in ticks:
		if sim.is_over():
			if not sim.revive():
				break
			actions += "r"
			sums.append(str(sim.checksum()))
			continue
		var tap := PlannerBot.aim(sim, rng) or not sim.state.started
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
	_lines.append(
		"run %s %d %d %d %s %s" % [name, seed_value, season, practice, actions, ",".join(sums)]
	)


## A SurvivalSearch: its winning taps, then those taps replayed as a run case.
func _search_case(name: String, seed_value: int, season: int, practice: int, ticks: int) -> void:
	var sim := GameSim.new(seed_value, season, practice)
	var search := SurvivalSearch.new()
	var ok := search.run(sim, ticks)
	var taps := ""
	for b in search.best_inputs:
		taps += str(b)
	_lines.append(
		(
			"search %s %d %d %d %d %d %d %s"
			% [
				name,
				seed_value,
				season,
				practice,
				ticks,
				int(ok),
				search.ticks_survived,
				taps if ok else "-"
			]
		)
	)
	if not ok:
		return
	var replay := GameSim.new(seed_value, season, practice)
	var sums := PackedStringArray()
	for b in search.best_inputs:
		replay.step(b == 1)
		sums.append(str(replay.checksum()))
	_lines.append(
		"run %s %d %d %d %s %s" % [name, seed_value, season, practice, taps, ",".join(sums)]
	)
