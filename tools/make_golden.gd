extends SceneTree
## Regenerates the golden replays from the gap-seeker bot.
##   godot --headless --path . -s res://tools/make_golden.gd
## Only run this after an intended gameplay change AND a GAMEPLAY_VERSION bump.

const OUT_DIR := "res://tests/replay/golden"
const SEEDS: Array[int] = [11, 2024, 31337, 65536, 4000000000]
## Bot stops tapping after this many ticks (about 40 s) so every run ends.
const ACTIVE_TICKS := 2400
## Runs that die, are revived and play on: [seed, ticks before, ticks after].
const REVIVED: Array = [[2024, 1200, 1500], [31337, 2000, 1500]]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var version := SimConfig.GAMEPLAY_VERSION
	for i in SEEDS.size():
		var replay := SimBots.play(SEEDS[i], SimBots.gap_seeker, i + 1, ACTIVE_TICKS)
		_save(replay, "g%d_seed_%d.json" % [version, SEEDS[i]])
	for i in REVIVED.size():
		var r: Array = REVIVED[i]
		var replay := SimBots.play_revived(r[0], SimBots.gap_seeker, i + 11, r[1], r[2])
		_save(replay, "g%d_revived_seed_%d.json" % [version, r[0]])
	quit(0)


func _save(replay: Replay, file: String) -> void:
	var path := OUT_DIR.path_join(file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(replay.to_dict(), "  ", false) + "\n")
	f.close()
	print(
		(
			"%s  score=%d ticks=%d taps=%d revives=%d"
			% [path, replay.score, replay.end_tick, replay.taps.size(), replay.revive_ticks.size()]
		)
	)
