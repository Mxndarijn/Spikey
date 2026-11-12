extends SceneTree
## Records runs for the FastSim parity check (tools/fastsim, the C# copy of
## sim/ for fast bots). The C# side replays every run and must get the same
## checksum on every tick.
##   godot --headless --path . -s res://tools/fastsim_parity.gd -- <out.txt> [quick|full]
##     [part parts]
## With `part parts` it records only its share of the cases (every parts-th,
## from part), so tools/fastsim.ps1 can record in several processes at once.
##
## Cases, one per line:
##   run <name> <seed> <season> <practice> <actions> <checksums>
##     actions: 0 wait, 1 tap, r revive (between steps, no tick); one
##     checksum (GameSim.checksum()) after each action, comma separated.
##     Then "w:<n>": the warnings on screen after each action
##     (GameSim.warnings()), all mixed into one number.
##   search <name> <seed> <season> <practice> <ticks> <ok> <survived> <taps>
##     SurvivalSearch from a fresh sim; the C# search must find the same taps.
##   case <name> <setup> <driver> <actions> <checksums>
##     A sim built by <setup>, then played as <actions> (as in `run`):
##       p:<seed>:<season>:<practice>:<variant>  GameSim.new with a forced variant
##       a:<room>:<variant>:<i>                   ArrivalBench.arrival (out of a portal)
##       r:<room>:<seed>:<exit>:<side>:<toward>:<y>  BotSetups.revived
##       cr:<room>:<seed>:<exit>:<side>:<y>       BotSetups.crawl_revived
##       gr:<seed>:<open>:<side>:<y>:<variant>    BotSetups.gates_revived
##       ir:<room id>:<seed>:<exit>:<side>:<variant>  BotSetups.isles_revived
##       n:<room id>:<seed>:<variant>:<points>    BotSetups.practice, score += points
##       b:<seed>:<season>:<score>:-              a run at <score> through a portal
##                                                (a boss's at every BOSS_EVERY)
##     (variant "-" for none). <driver> is who chose the taps: "replay" (C#
##     only replays them), "gap" (SimBots.gap_seeker, SimRng 7, revives when it
##     can), "tap:<seed>" (SimBots.random_tapper, until the run ends) or
##     "planner:<seed>:<horizon>:<rollouts>:<hold>:<after>" (holds its height
##     <hold> ticks as ArrivalBench, then PlannerBot for <after> ticks): for a
##     bot, the C# bot must choose the same taps.
##   csearch <name> <setup> <ticks> <ok> <survived> <taps>
##     SurvivalSearch from a <setup> sim, as `search`.
##   qsearch <name> <setup> <ticks> <ok> <survived> <taps>
##     The same with QuickSearch (C# run_quick).
## Coverage: every room in practice (a gap-seeking bot and a SurvivalSearch
## line, so the bird lives long enough to see exits and portals), and full runs
## through the portals in every season, with a revive. For the bot checks on
## FastSim (`fastsim check`, Checks.cs): every room variant forced in practice,
## a portal arrival into every room variant, a revive in every room, every
## other sim those checks start from (BotSetups), and the bots and searches
## they use. No GDScript test plays a bot any more, so this is what ties the
## checks to the real game code.

const AIM_TICKS := 600
const ROOM_SEARCH_TICKS := 700
const RUN_SEARCH_TICKS := 4000
const RUN_SEEDS := 3
## Ticks for each forced variant, portal arrival and revive case.
const VARIANT_TICKS := 300
const ARRIVAL_TICKS := 200
const REVIVE_TICKS := 240
## Ticks of each run through a boss portal (all three phases).
const BOSS_TICKS := 1500
const EXITS: Array[String] = ["none", "open", "ghost"]

var _lines := PackedStringArray()
var _part := 0
var _parts := 1
## Cases asked for so far (each recorded only by its own part).
var _asked := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://fastsim_parity.txt"
	var quick := args.size() > 1 and args[1] == "quick"
	if args.size() > 3:
		_part = int(args[2])
		_parts = maxi(1, int(args[3]))
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
	var share := "" if _parts == 1 else " (part %d of %d)" % [_part + 1, _parts]
	print(
		(
			"fastsim parity: %d cases in %.0f s%s -> %s"
			% [_lines.size(), (Time.get_ticks_msec() - start) / 1000.0, share, out]
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
		var ys := BotSetups.ENTRY_YS
		var r := (
			"r:%d:%d:%s:%d:%d:%d"
			% [
				index,
				9000 + index,
				exit,
				(index / EXITS.size()) % 2,
				index % 2,
				ys[(index / 2) % ys.size()]
			]
		)
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
	var r := "r:%d:9001:open:1:0:%d" % [RoomCatalog.first_index(), SimConfig.BIRD_START_Y]
	_csearch_case("csearch_revive", r, SimConfig.ARRIVAL_HOLD + 180)
	_room_check_cases(quick)


## The setups of the crawl, gates, isles and runs checks (Checks.cs).
func _room_check_cases(quick: bool) -> void:
	var crawl := RoomCatalog.index_of("crawl")
	var top := SimConfig.slot_center_y(1)
	var bottom := SimConfig.slot_center_y(SimConfig.SLOT_COUNT - 2)
	var hard := [["ghost", 1, top], ["ghost", 0, bottom], ["open", 1, top], ["open", 0, bottom]]
	for k in hard.size():
		var c: Array = hard[k]
		var cr := "cr:%d:%d:%s:%d:%d" % [crawl, 7 + k, c[0], c[1], c[2]]
		_setup_case("crawl_revive_%d" % k, cr, REVIVE_TICKS, 0)
	for k in 8:
		var variant := "classic" if k < 4 else "single-small"
		var gr := (
			"gr:%d:%d:%d:%d:%s"
			% [101 + k, k % 2, (k / 2) % 2, SimConfig.slot_center_y(1 + k), variant]
		)
		_setup_case("gates_revive_%d" % k, gr, REVIVE_TICKS, 0)
		var n := "n:gates:%d:%s:%d" % [500 + k * 37, variant, SimConfig.POINTS_PER_ROOM - 1 - k % 2]
		_setup_case("gates_near_%d" % k, n, VARIANT_TICKS, 0)
	for v: String in ["classic", "drifting", "one-big"]:
		var ir := "ir:isles:%d:open:%d:%s" % [15 + v.length(), v.length() % 2, v]
		_setup_case("isles_revive_" + v, ir, REVIVE_TICKS, 0)
		_setup_case("isles_near_" + v, "n:isles:%d:%s:28" % [7 + v.length(), v], VARIANT_TICKS, 0)
	for v: String in ["classic", "drifting", "golden"]:
		_setup_case("eggs_near_" + v, "n:eggs:%d:%s:28" % [3 + v.length(), v], VARIANT_TICKS, 0)
	for k in 3 if quick else 6:
		var b := "b:%d:%d:%d:-" % [77 + k * 13, Seasons.NONE, SimConfig.BOSS_EVERY * (1 + k % 3)]
		_setup_case("boss_portal_%d" % k, b, BOSS_TICKS, 0)
		_gap_case("gap_boss_%d" % k, b)
	for k in 2 if quick else 8:
		_tap_case("tap_%d" % k, "p:%d:%d:-1:-" % [1001 + k * 7, Seasons.NONE], k + 1)
	_qsearch_case("qsearch_isles", "n:isles:322:drifting:28", 200)
	_qsearch_case("qsearch_revive", "ir:isles:127:open:1:one-big", SimConfig.ARRIVAL_HOLD + 60)


## Whether this process records the next case (see `part parts`).
func _mine() -> bool:
	_asked += 1
	return _asked % _parts == _part


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
			return BotSetups.revived(int(f[1]), int(f[2]), f[3], int(f[4]), int(f[5]), int(f[6]))
		"cr":
			return BotSetups.crawl_revived(int(f[1]), int(f[2]), f[3], int(f[4]), int(f[5]))
		"gr":
			return BotSetups.gates_revived(int(f[1]), f[2] == "1", int(f[3]), int(f[4]), f[5])
		"ir":
			return BotSetups.isles_revived(f[1], int(f[2]), f[3], int(f[4]), f[5])
		"n":
			var sim := BotSetups.practice(f[1], int(f[2]), "" if f[3] == "-" else f[3])
			sim.state.score += int(f[4])
			return sim
		"b":
			var sim := GameSim.new(int(f[1]), int(f[2]))
			sim.step(true)
			sim.state.score = int(f[3])
			sim._go_through(1, SimState.ExitKind.NORMAL, 320 * SimConfig.SUB)
			return sim
	return null


## `hold` ticks holding the height (ArrivalBench.hold), then PlannerBot.aim.
func _setup_case(name: String, text: String, ticks: int, hold: int) -> void:
	if not _mine():
		return
	var sim := setup(text)
	var rng := SimRng.new(ticks + name.length())
	var y0 := sim.state.y
	var actions := ""
	var sums := PackedStringArray()
	var w := SimHash.SEED
	for t in ticks:
		if sim.is_over():
			if not sim.revive():
				break
			actions += "r"
			sums.append(str(sim.checksum()))
			w = _warn_mix(w, sim)
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
		w = _warn_mix(w, sim)
	_lines.append("case %s %s replay %s %s" % [name, text, actions, _sums(sums, w)])


## SimBots.gap_seeker as the points check plays it (revives included).
func _gap_case(name: String, text: String) -> void:
	if not _mine():
		return
	var sim := setup(text)
	var bot := SimRng.new(7)
	var actions := ""
	var sums := PackedStringArray()
	var w := SimHash.SEED
	while sim.state.tick < 1500:
		if sim.is_over():
			if not (sim.can_revive() and sim.revive()):
				break
			actions += "r"
			sums.append(str(sim.checksum()))
			w = _warn_mix(w, sim)
		var tap := SimBots.gap_seeker(sim, bot)
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
		w = _warn_mix(w, sim)
	_lines.append("case %s %s gap %s %s" % [name, text, actions, _sums(sums, w)])


## ArrivalBench.play's player: holds `hold` ticks, then a PlannerBot.
func _planner_case(
	name: String, text: String, bot_seed: int, horizon: int, rollouts: int, hold: int, after: int
) -> void:
	if not _mine():
		return
	var sim := setup(text)
	var bot := PlannerBot.new(bot_seed, horizon, rollouts)
	var y0 := sim.state.y
	var actions := ""
	var sums := PackedStringArray()
	var w := SimHash.SEED
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
		w = _warn_mix(w, sim)
	var driver := "planner:%d:%d:%d:%d:%d" % [bot_seed, horizon, rollouts, hold, after]
	_lines.append("case %s %s %s %s %s" % [name, text, driver, actions, _sums(sums, w)])


## SimBots.random_tapper (as Checks.cs Runs plays it) until the run ends.
func _tap_case(name: String, text: String, bot_seed: int) -> void:
	if not _mine():
		return
	var sim := setup(text)
	var bot := SimRng.new(bot_seed)
	var actions := ""
	var sums := PackedStringArray()
	var w := SimHash.SEED
	while not sim.is_over() and sim.state.tick < 20000:
		var tap := SimBots.random_tapper(sim, bot)
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
		w = _warn_mix(w, sim)
	_lines.append("case %s %s tap:%d %s %s" % [name, text, bot_seed, actions, _sums(sums, w)])


func _qsearch_case(name: String, text: String, ticks: int) -> void:
	_csearch_case(name, text, ticks, true)


func _csearch_case(name: String, text: String, ticks: int, quick := false) -> void:
	if not _mine():
		return
	var search: SurvivalSearch = QuickSearch.new() if quick else SurvivalSearch.new()
	var ok := search.run(setup(text), ticks)
	var taps := ""
	for b in search.best_inputs:
		taps += str(b)
	_lines.append(
		(
			"%s %s %s %d %d %d %s"
			% [
				"qsearch" if quick else "csearch",
				name,
				text,
				ticks,
				int(ok),
				search.ticks_survived,
				taps if ok else "-"
			]
		)
	)


## A gap-seeking bot (PlannerBot.aim) with a revive when it dies in a real run.
func _aim_case(name: String, seed_value: int, season: int, practice: int, ticks: int) -> void:
	if not _mine():
		return
	var sim := GameSim.new(seed_value, season, practice)
	var rng := SimRng.new(seed_value)
	var actions := ""
	var sums := PackedStringArray()
	var w := SimHash.SEED
	for t in ticks:
		if sim.is_over():
			if not sim.revive():
				break
			actions += "r"
			sums.append(str(sim.checksum()))
			w = _warn_mix(w, sim)
			continue
		var tap := PlannerBot.aim(sim, rng) or not sim.state.started
		sim.step(tap)
		actions += "1" if tap else "0"
		sums.append(str(sim.checksum()))
		w = _warn_mix(w, sim)
	_lines.append(
		"run %s %d %d %d %s %s" % [name, seed_value, season, practice, actions, _sums(sums, w)]
	)


## A SurvivalSearch: its winning taps, then those taps replayed as a run case.
func _search_case(name: String, seed_value: int, season: int, practice: int, ticks: int) -> void:
	if not _mine():
		return
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
	var w := SimHash.SEED
	for b in search.best_inputs:
		replay.step(b == 1)
		sums.append(str(replay.checksum()))
		w = _warn_mix(w, replay)
	_lines.append(
		"run %s %d %d %d %s %s" % [name, seed_value, season, practice, taps, _sums(sums, w)]
	)


## The checksums of a run or case, then " w:<n>": every tick's warnings
## (GameSim.warnings) mixed into one number, so the C# copy must show the same tells.
static func _sums(sums: PackedStringArray, w: int) -> String:
	return "%s w:%d" % [",".join(sums), w]


static func _warn_mix(w: int, sim: GameSim) -> int:
	var all := sim.warnings()
	var out := SimHash.mix(w, all.size())
	for v: int in all:
		out = SimHash.mix(out, v)
	return out
