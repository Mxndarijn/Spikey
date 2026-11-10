extends TestCase
## A save that breaks (a crash mid-write, a full disk, a bad edit) never costs
## the player their progress.

const TEST_PATH := "user://test_safe_file.json"


func test_writes_and_reads_back() -> void:
	SafeFile.remove(TEST_PATH)
	assert_true(SafeFile.write_json(TEST_PATH, {"coins": 5}))
	assert_eq((SafeFile.read_json(TEST_PATH) as Dictionary).coins, 5.0)
	assert_false(FileAccess.file_exists(TEST_PATH + SafeFile.TMP), "no temp file left")
	SafeFile.remove(TEST_PATH)


func test_the_last_good_save_stays_as_a_backup() -> void:
	SafeFile.remove(TEST_PATH)
	SafeFile.write_json(TEST_PATH, {"coins": 1})
	SafeFile.write_json(TEST_PATH, {"coins": 2})
	var bak: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH + SafeFile.BAK))
	assert_eq((bak as Dictionary).coins, 1.0, "the save before the last one")
	SafeFile.remove(TEST_PATH)


func test_a_broken_save_loads_the_backup_and_is_kept_aside() -> void:
	SafeFile.remove(TEST_PATH)
	var p := Profile.new()
	p.coins = 40
	p.save(TEST_PATH)
	p.coins = 50
	p.save(TEST_PATH)
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{"coins": 9')
	f.close()
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.coins, 40, "the backup, not a fresh profile")
	assert_true(FileAccess.file_exists(TEST_PATH + SafeFile.BROKEN), "the broken file is kept")
	back.save(TEST_PATH)
	assert_eq(
		FileAccess.get_file_as_string(TEST_PATH + SafeFile.BROKEN),
		'{"coins": 9',
		"saving again doesn't touch it"
	)
	SafeFile.remove(TEST_PATH)


func test_an_empty_save_is_not_read_as_a_fresh_start() -> void:
	SafeFile.remove(TEST_PATH)
	var p := Profile.new()
	p.best_score = 33
	p.save(TEST_PATH)
	p.save(TEST_PATH)
	FileAccess.open(TEST_PATH, FileAccess.WRITE).close()
	assert_eq(Profile.load_or_new(TEST_PATH).best_score, 33)
	SafeFile.remove(TEST_PATH)


func test_keys_from_a_newer_version_survive_a_save() -> void:
	var p := Profile.from_dict({"version": Profile.VERSION + 1, "coins": 3, "pets": ["cat"]})
	assert_eq(p.coins, 3)
	var d := p.to_dict()
	assert_eq(d.get("pets"), ["cat"], "kept as it was")
	assert_eq(d.version, Profile.VERSION + 1, "and so is its version")


func test_older_versions_load_and_save_as_this_one() -> void:
	var p := Profile.from_dict({"version": 1, "coins": 8})
	assert_eq(p.coins, 8)
	assert_eq(p.to_dict().version, Profile.VERSION)
