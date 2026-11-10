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
##   case <name> <setup> <driver> <actions> <checksums>
##     A sim built by <setup>, then played as <actions> (as in `run`):
##       p:<seed>:<season>:<practice>:<variant>  GameSim.new with a forced variant
##       a:<room>:<variant>:<i>                   ArrivalBench.arrival (out of a portal)
##       r:<room>:<seed>:<exit>:<side>            test_revive_survivable.gd revived()
##     (variant "-" for none). <driver> is who chose the taps: "replay" (C#
##     only replays them), "gap" (SimBots.gap_seeker, SimRng 7, revives when it
##     can) or "planner:<seed>:<horizon>:<rollouts>:<hold>:<after>" (holds
##     its height <hold> ticks as ArrivalBench, then PlannerBot for <after>
##     ticks): for a bot, the C# bot must choose the same taps.
##   csearch <name> <setup> <ticks> <ok> <survived> <taps>
##     SurvivalSearch from a <setup> sim, as `search`.
## Coverage: every room in practice (a gap-seeking bot and a SurvivalSearch
## line, so the bird lives long enough to see exits and portals), and full runs
## through the portals in every season, with a revive. For the bot checks on
## FastSim (`fastsim check`, Checks.cs): every room variant forced in practice,
## a portal arrival into every room variant, a revive in every room, and the
## bots and searches those checks use.

const AIM_TICKS := 600
const ROOM_SEARCH_TICKS := 700
const RUN_SEARCH_TICKS := 4000
const RUN_SEEDS := 3
## Ticks for each forced variant, portal arrival and revive case.
const VARIANT_TICKS := 300
const ARRIVAL_TICKS := 200
const REVIVE_TICKS := 240
const EXITS: Array[String] = ["none", "open", "ghost"]
const RevivedTest := preload("res://tests/sim/test_revive_survivable.gd")

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
	_check_cases(quick)
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


## What the FastSim bot checks (Checks.cs) rely on: every (room, variant) of
## ArrivalBench.cases() forced in practice and out of a portal, a revive in
## every room, and their bots and searches.
func _check_cases(quick: bool) -> void:
	var cases := ArrivalBench.cases()
	var rooms := RoomCatalog.all()
	for c in cases.size():
		var index: int = cases[c][0]
		var variant: String = cases[c][1]
		var def: RoomDef = rooms[index]
		var v := variant if variant != "" else "-"
		var label := def.id + ("" if variant == "" else "/" + variant)
		var p := "p:%d:%d:%d:%s" % [500 + c * 37, def.season, index, v]
		_setup_case("variant_" + label, p, VARIANT_TICKS, 0)
		# Arrival heights, sides and scores spread over the cases.
		var a := "a:%d:%s:%d" % [index, v, c % 32]
		_setup_case("arrival_" + label, a, ARRIVAL_TICKS, ArrivalBench.EARLY_DELAY)
	for index in rooms.size():
		var exit := EXITS[index % EXITS.size()]
		var r := "r:%d:%d:%s:%d" % [index, 9000 + index, exit, (index / EXITS.size()) % 2]
		_setup_case("revive_" + rooms[index].id, r, REVIVE_TICKS, 0)
	# The bots and searches of the checks, on a few cases.
	var step := 1 if not quick else maxi(1, cases.size() / 6)
	for c in range(0, cases.size(), step):
		var index: int = cases[c][0]
		var v: String = cases[c][1] if cases[c][1] != "" else "-"
		var label := "%s_%d" % [rooms[index].id, c]
		var p := "p:%d:%d:%d:%s" % [1000 + c, rooms[index].season, index, v]
		_gap_case("gap_" + label, p)
		var a := "a:%d:%s:%d" % [index, v, c % 32]
		_planner_case("planner_" + label, a, c + 1, 45, 2, ArrivalBench.EARLY_DELAY, 120)
		_csearch_case("csearch_" + label, p, 300)
	_gap_case("gap_run", "p:4242:%d:-1:-" % Seasons.NONE)
	var r := "r:%d:9001:open:1" % RoomCatalog.first_index()
	_csearch_case("csearch_revive", r, SimConfig.ARRIVAL_HOLD + 180)


## A sim from a `case` setup string.
static func setup(text: String) -> GameSim:
	var f := text.split(":")
	var variant := "" if f[-1] == "-" else f[-1]
	match f[0]:
		"p":
			return GameSim.new(int(f[1]), int(f[2]), int(f[3]), variant)
		"a":
			return ArrivalBench.arrival(int(f[1]), int(f[3]), "" if f[2] == "-" else f[2])
		"r":
			return RevivedTest.revived(int(f[1]), int(f[2]), f[3], int(f[4]))
	return null


## `hold` ticks holding the height (ArrivalBench.hold), then PlannerBot.aim.
func _setup_case(name: String, text: String, ticks: int, hold: int) -> void:
	var sim := setup(text)
	var rng := SimRng.new(ticks + name.length())
	var y0 := sim.state.y
	var actions := ""
	var sums := PackedStringArray()
	for t in ticks:
		if sim.is_over():
			if not sim.revive():
				break
			actions += "r"
			sums.append(str(sim.checksum()))
			continue
		var tap: bool
		if t < hold:
			var g := sim.room.gravity
			tap = (sim.state.y - y0) * g > 0 and sim.state.vy * g >= 0
		else:
			tap = PlannerBot.aim(sim, rng) or not sim.state.started
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
	_lines.append("case %s %s replay %s %s" % [name, text, actions, ",".join(sums)])


## SimBots.gap_seeker as test_room_points_cap.gd plays it (revives included).
func _gap_case(name: String, text: String) -> void:
	var sim := setup(text)
	var bot := SimRng.new(7)
	var actions := ""
	var sums := PackedStringArray()
	while sim.state.tick < 1500:
		if sim.is_over():
			if not (sim.can_revive() and sim.revive()):
				break
			actions += "r"
			sums.append(str(sim.checksum()))
		var tap := SimBots.gap_seeker(sim, bot)
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
	_lines.append("case %s %s gap %s %s" % [name, text, actions, ",".join(sums)])


## ArrivalBench.play's player: holds `hold` ticks, then a PlannerBot.
func _planner_case(
	name: String, text: String, bot_seed: int, horizon: int, rollouts: int, hold: int, after: int
) -> void:
	var sim := setup(text)
	var bot := PlannerBot.new(bot_seed, horizon, rollouts)
	var y0 := sim.state.y
	var actions := ""
	var sums := PackedStringArray()
	var n := 0
	while n < hold + after and not sim.is_over():
		var tap: bool
		if n < hold:
			var g := sim.room.gravity
			tap = (sim.state.y - y0) * g > 0 and sim.state.vy * g >= 0
		else:
			tap = bot.decide(sim)
		sim.step(tap)
		n += 1
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
	var driver := "planner:%d:%d:%d:%d:%d" % [bot_seed, horizon, rollouts, hold, after]
	_lines.append("case %s %s %s %s %s" % [name, text, driver, actions, ",".join(sums)])


func _csearch_case(name: String, text: String, ticks: int) -> void:
	var search := SurvivalSearch.new()
	var ok := search.run(setup(text), ticks)
	var taps := ""
	for b in search.best_inputs:
		taps += str(b)
	_lines.append(
		(
			"csearch %s %s %d %d %d %s"
			% [name, text, ticks, int(ok), search.ticks_survived, taps if ok else "-"]
		)
	)


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
