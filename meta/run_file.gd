class_name RunFile
extends RefCounted
## One recorded run to render or check: the replay (gameplay version, seed,
## season, taps, revives and the result it claims) plus how it looked (the
## loadout: one id per ItemKind) and the look settings. The one file a bot
## writes when it wants a run rendered (docs/RENDERING.md). FastSim-RS bots
## write the same JSON (tools/fastsim-rs/fastsim/src/bots/run_file.rs).
##
## JSON: Replay.to_dict() plus "format", "format_version", "name", "loadout"
## and "settings", so a run file is also a leaderboard run (main.play_replay).

const FORMAT := "flapjaw_run"
const FORMAT_VERSION := 1
## The look settings a run file may set (PlayerSettings fields, all bools).
## The longest run check() replays (4 hours of play).
const LONG_MAX_TICKS := 4 * 60 * 60 * SimConfig.TICKS_PER_SECOND
const SETTINGS: Array[String] = ["color_blind_spikes", "reduced_flashing", "large_buttons"]

var replay := Replay.new()
## Shown on the replay chip ("Replay: <name>, <score>").
var name := ""
## ItemKind -> id. A kind left out uses the game's default.
var loadout: Dictionary[String, String] = {}
## SETTINGS name -> on. Left out: off.
var settings: Dictionary[String, bool] = {}
## Why the file can't be used, set by from_dict(); "" when it reads fine.
var read_problem := ""


static func from_replay(
	p_replay: Replay, p_loadout: Dictionary = {}, p_name: String = ""
) -> RunFile:
	var f := RunFile.new()
	f.replay = p_replay
	f.name = p_name
	for kind: Variant in p_loadout:
		f.loadout[str(kind)] = str(p_loadout[kind])
	return f


func to_dict() -> Dictionary:
	var d := replay.to_dict()
	d["format"] = FORMAT
	d["format_version"] = FORMAT_VERSION
	d["name"] = name
	d["loadout"] = loadout.duplicate()
	d["settings"] = settings.duplicate()
	return d


static func from_dict(d: Dictionary) -> RunFile:
	var f := RunFile.new()
	if str(d.get("format", "")) != FORMAT:
		f.read_problem = 'not a run file (format must be "%s")' % FORMAT
		return f
	if int(d.get("format_version", -1)) != FORMAT_VERSION:
		f.read_problem = (
			"run file format_version %d, this build reads %d"
			% [int(d.get("format_version", -1)), FORMAT_VERSION]
		)
		return f
	for key in ["seed", "taps", "score", "end_tick"]:
		if not d.has(key):
			f.read_problem = 'run file has no "%s"' % key
			return f
	f.replay = Replay.from_dict(d)
	f.name = str(d.get("name", ""))
	var look: Variant = d.get("loadout", {})
	if not look is Dictionary:
		f.read_problem = "loadout must be an object"
		return f
	for kind: Variant in look:
		if not str(kind) in ItemKind.ALL:
			f.read_problem = (
				'unknown loadout kind "%s" (kinds: %s)' % [kind, ", ".join(ItemKind.ALL)]
			)
			return f
		f.loadout[str(kind)] = str(look[kind])
	var flags: Variant = d.get("settings", {})
	if not flags is Dictionary:
		f.read_problem = "settings must be an object"
		return f
	for key: Variant in flags:
		if not str(key) in SETTINGS:
			f.read_problem = 'unknown setting "%s" (settings: %s)' % [key, ", ".join(SETTINGS)]
			return f
		f.settings[str(key)] = bool(flags[key])
	return f


## Reads a run file; read_problem says what is wrong with it, if anything.
static func load_file(path: String) -> RunFile:
	if not FileAccess.file_exists(path):
		var missing := RunFile.new()
		missing.read_problem = "no run file at %s" % path
		return missing
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		var bad := RunFile.new()
		bad.read_problem = "run file is not a JSON object: %s" % path
		return bad
	return from_dict(parsed as Dictionary)


func save_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  ", false) + "\n")
	f.close()
	return true


## Re-simulates the run and checks it against what the file claims
## (Replay.verify: gameplay version, taps, score, coins, end tick, checksum).
## {ok, reason, score, coins, end_tick, checksum}.
## A run longer than SimConfig.MAX_TICKS (the 4 hours the leaderboard
## verifier replays) is replayed here to its end, up to LONG_MAX_TICKS: the game
## itself plays on past that, so a long bot run still renders.
func check() -> Dictionary:
	if not read_problem.is_empty():
		return {"ok": false, "reason": read_problem}
	if replay.end_tick <= SimConfig.MAX_TICKS:
		return replay.verify()
	return _check_long()


## Replay.verify's checks, with Replay.simulate's loop run to LONG_MAX_TICKS.
func _check_long() -> Dictionary:
	var r := replay
	var out := {"ok": false, "reason": "", "score": 0, "coins": 0, "end_tick": 0, "checksum": 0}
	if r.gameplay_version != SimConfig.GAMEPLAY_VERSION:
		out.reason = "unsupported gameplay_version %d" % r.gameplay_version
		return out
	for i in r.taps.size():
		if r.taps[i] < 0 or (i > 0 and r.taps[i] <= r.taps[i - 1]):
			out.reason = "taps must be ascending and non-negative"
			return out
	if r.revive_ticks.size() > SimConfig.MAX_REVIVES:
		out.reason = "too many revives"
		return out
	var sim := GameSim.new(r.seed_value, r.season)
	var next := 0
	var next_revive := 0
	while sim.state.tick < LONG_MAX_TICKS:
		if sim.is_over():
			var due := (
				next_revive < r.revive_ticks.size()
				and r.revive_ticks[next_revive] == sim.state.tick
			)
			if not due or not sim.revive():
				break
			next_revive += 1
		var tap := next < r.taps.size() and r.taps[next] == sim.state.tick
		if tap:
			next += 1
		sim.step(tap)
	out.score = sim.state.score
	out.coins = sim.state.coins
	out.end_tick = sim.state.tick
	out.checksum = sim.checksum()
	if not sim.is_over():
		out.reason = "run did not end"
	elif sim.state.score != r.score:
		out.reason = "score mismatch (claimed %d, replayed %d)" % [r.score, sim.state.score]
	elif sim.state.coins != r.coins:
		out.reason = "coins mismatch (claimed %d, replayed %d)" % [r.coins, sim.state.coins]
	elif sim.state.tick != r.end_tick:
		out.reason = "end_tick mismatch"
	elif r.checksum != 0 and r.checksum != out.checksum:
		out.reason = "checksum mismatch"
	else:
		out.ok = true
	return out


## Turns the file's look settings on in `p` (the rest off).
func apply_settings(p: PlayerSettings) -> void:
	p.color_blind_spikes = settings.get("color_blind_spikes", false)
	p.reduced_flashing = settings.get("reduced_flashing", false)
	p.large_buttons = settings.get("large_buttons", false)
