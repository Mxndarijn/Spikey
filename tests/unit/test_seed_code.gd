extends TestCase
## SeedCode: a seed code holds the random part, the season and the gameplay
## version, so one code always plays the same map.


func _round_trip(random: int, season: int, version: int) -> void:
	var code := SeedCode.encode(random, season, version)
	assert_eq(code.length(), SeedCode.LENGTH + 1, "10 characters and a dash: " + code)
	var parts := SeedCode.decode(code)
	assert_true(parts != null, "decodes " + code)
	if parts == null:
		return
	assert_eq(parts.random, random, code)
	assert_eq(parts.season, season, code)
	assert_eq(parts.version, version, code)
	assert_false(parts.legacy, code)


func test_every_season_and_edge_round_trips() -> void:
	for season in range(Seasons.NONE, Seasons.COUNT):
		for random: int in [0, 1, 5000, 2147483648, 3392377610, SeedCode.MAX_RANDOM]:
			for version: int in [0, 21, 22, SeedCode.MAX_VERSION]:
				_round_trip(random, season, version)


func test_random_seeds_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		var random := rng.randi()
		_round_trip(
			random, rng.randi_range(Seasons.NONE, Seasons.COUNT - 1), rng.randi_range(0, 1023)
		)


func test_the_first_character_is_always_a_check_letter() -> void:
	for random in 500:
		var code := SeedCode.encode(random * 8589931, Seasons.NONE, 21)
		assert_true(SeedCode.CHECKS.contains(code[0]), code)


func test_out_of_range_parts_have_no_code() -> void:
	assert_eq(SeedCode.encode(-1, Seasons.NONE, 21), "")
	assert_eq(SeedCode.encode(SeedCode.MAX_RANDOM + 1, Seasons.NONE, 21), "")
	assert_eq(SeedCode.encode(1, Seasons.COUNT, 21), "")
	assert_eq(SeedCode.encode(1, -2, 21), "")
	assert_eq(SeedCode.encode(1, Seasons.NONE, SeedCode.MAX_VERSION + 1), "")


func test_typing_is_forgiving() -> void:
	var code := SeedCode.encode(3392377610, Seasons.HALLOWEEN, 21)
	var plain := code.replace("-", "")
	var want := SeedCode.decode(code)
	for typed: String in [
		plain,
		plain.to_lower(),
		"  " + code + " ",
		plain.substr(0, 5) + " " + plain.substr(5),
		plain.replace("0", "O").replace("1", "l"),
		"Seed %s · Halloween · v21" % code,
	]:
		var got := SeedCode.decode(typed)
		assert_true(got != null, typed)
		if got != null:
			assert_eq(
				[got.random, got.season, got.version],
				[want.random, want.season, want.version],
				typed
			)


func test_a_typo_is_caught_by_the_check_letter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var caught := 0
	var tries := 2000
	for i in tries:
		var code := SeedCode.encode(rng.randi(), Seasons.NONE, 21).replace("-", "")
		var at := rng.randi_range(1, SeedCode.LENGTH - 1)
		var c := SeedCode.DIGITS[(SeedCode.DIGITS.find(code[at]) + rng.randi_range(1, 31)) % 32]
		var typo := code.substr(0, at) + c + code.substr(at + 1)
		if SeedCode.decode(typo) == null:
			caught += 1
	# 1 in 22 slips through at worst.
	assert_true(caught > tries * 90 / 100, "caught %d of %d typos" % [caught, tries])
	assert_eq(SeedCode.problem("B0000-00000"), "Not a seed: check the letters")


func test_old_seed_numbers_still_parse() -> void:
	var p := SeedCode.decode("3392377610")
	assert_true(p != null and p.legacy)
	assert_eq(p.random, 3392377610)
	assert_eq(p.season, Seasons.NONE, "an old seed holds no season")
	assert_eq(p.version, -1, "nor a version")
	p = SeedCode.decode("Seed 98765 · v11")
	assert_eq(p.random, 98765, "the old game over line")
	assert_eq(p.version, 11, "with its version")
	assert_eq(SeedCode.decode("0").random, 0)
	assert_eq(SeedCode.decode(str(SeedCode.MAX_RANDOM)).random, SeedCode.MAX_RANDOM)
	assert_true(SeedCode.decode(str(SeedCode.MAX_RANDOM + 1)) == null, "too big")
	assert_true(SeedCode.decode("99999999999999999999999") == null, "far too big")
	assert_true(SeedCode.decode("") == null)
	assert_true(SeedCode.decode("seed") == null)


func test_describe() -> void:
	assert_eq(SeedCode.describe(SeedCode.Parts.new(1, Seasons.HALLOWEEN, 21)), "Halloween · v21")
	assert_eq(SeedCode.describe(SeedCode.Parts.new(1, Seasons.NONE, 21)), "No season · v21")
	var old := SeedCode.decode("123")
	assert_eq(SeedCode.describe(old), "Old seed")


## Pinned codes: changing the format would make every shared seed play wrong.
func test_known_codes_stay_the_same() -> void:
	assert_eq(SeedCode.encode(3392377610, Seasons.NONE, 21), "ES8SS-62G0N")
	assert_eq(SeedCode.encode(3392377610, Seasons.HALLOWEEN, 21), "RS8SS-62H0N")
	assert_eq(SeedCode.encode(5000, Seasons.SUMMER, 21), "W0001-7250N")
	assert_eq(SeedCode.encode(0, Seasons.NONE, 0), "A0000-00000")
