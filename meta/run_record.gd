class_name RunRecord
extends RefCounted
## One of the player's own runs, kept on the phone (RunHistory): its replay
## and look (a RunFile: seed, season, taps, revives, gameplay version, loadout)
## plus what Your runs shows about it: when it was played, the world, how many
## rooms it reached, the score it was revived at and whether it set a best.

## Set by RunHistory.add(); higher = played later.
var id := 0
var run := RunFile.new()
## Unix time (seconds) the run ended.
var played_at := 0
## The world (ItemKind.WORLD id) it was played in.
var world := ""
## Rooms reached, the first room included.
var rooms := 1
## The score the bird was revived at, -1 when it wasn't.
var revived_at := -1
## The run set a new best score when it was played.
var best := false
## Kept in Saved until the player removes it (RunHistory.SAVED_MAX).
var saved := false


static func make(
	replay: Replay,
	loadout: Dictionary,
	p_played_at: int,
	p_rooms: int,
	p_revived_at: int = -1,
	p_best: bool = false
) -> RunRecord:
	var r := RunRecord.new()
	r.run = RunFile.from_replay(replay, loadout)
	r.played_at = p_played_at
	r.world = str(loadout.get(ItemKind.WORLD, ""))
	r.rooms = maxi(1, p_rooms)
	r.revived_at = p_revived_at
	r.best = p_best
	return r


func score() -> int:
	return run.replay.score


func revived() -> bool:
	return revived_at >= 0


## Only a run from this gameplay version replays the way it was played; an
## older one would play out differently, so it is shown but can't be watched.
func watchable() -> bool:
	return run.read_problem.is_empty() and run.replay.gameplay_version == SimConfig.GAMEPLAY_VERSION


func to_dict() -> Dictionary:
	return {
		"id": id,
		"run": run.to_dict(),
		"played_at": played_at,
		"world": world,
		"rooms": rooms,
		"revived_at": revived_at,
		"best": best,
		"saved": saved,
	}


## JSON numbers arrive as floats; they are made ints again here.
static func from_dict(d: Dictionary) -> RunRecord:
	var r := RunRecord.new()
	r.id = int(d.get("id", 0))
	var run_data: Variant = d.get("run", {})
	r.run = RunFile.from_dict(run_data if run_data is Dictionary else {})
	r.played_at = int(d.get("played_at", 0))
	r.world = str(d.get("world", ""))
	r.rooms = maxi(1, int(d.get("rooms", 1)))
	r.revived_at = int(d.get("revived_at", -1))
	r.best = bool(d.get("best", false))
	r.saved = bool(d.get("saved", false))
	return r
