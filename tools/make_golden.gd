extends SceneTree
## Regenerates the golden replays from the gap-seeker bot.
##   godot --headless --path . -s res://tools/make_golden.gd
## Only run this after an intended gameplay change AND a GAMEPLAY_VERSION bump.

const OUT_DIR := "res://tests/replay/golden"
const SEEDS: Array[int] = [11, 2024, 31337, 65536, 4000000000]
## Bot stops tapping after this many ticks (about 40 s) so every run ends.
const ACTIVE_TICKS := 2400


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for i in SEEDS.size():
		var replay := SimBots.play(SEEDS[i], SimBots.gap_seeker, i + 1, ACTIVE_TICKS)
		var path := OUT_DIR.path_join("g%d_seed_%d.json" % [SimConfig.GAMEPLAY_VERSION, SEEDS[i]])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(replay.to_dict(), "  ", false) + "\n")
		f.close()
		print(
			(
				"%s  score=%d ticks=%d taps=%d"
				% [path, replay.score, replay.end_tick, replay.taps.size()]
			)
		)
	quit(0)
