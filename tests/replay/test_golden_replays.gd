extends TestCase
## Saved runs must replay to exactly the same score, end tick and checksum.
## A failure means gameplay changed. If that was intended: bump
## SimConfig.GAMEPLAY_VERSION, then regenerate with tools/make_golden.gd.

const GOLDEN_DIR := "res://tests/replay/golden"


func test_golden_replays_match() -> void:
	var dir := DirAccess.open(GOLDEN_DIR)
	assert_true(dir != null, "golden dir exists")
	if dir == null:
		return
	var count := 0
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		count += 1
		var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(GOLDEN_DIR.path_join(file))
		)
		if not data is Dictionary:
			fail("%s: invalid JSON" % file)
			continue
		var replay := Replay.from_dict(data)
		var result := replay.verify()
		assert_true(result.ok, "%s: %s" % [file, result.reason])
	assert_true(count >= 3, "at least 3 golden replays (found %d)" % count)
