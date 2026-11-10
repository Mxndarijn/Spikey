extends TestCase
## The leaderboard name filter: bad words are caught even with look-alike digits,
## repeated letters or dots between them; normal names with short words inside
## them pass; and the game's list matches the database migration's.

const MIGRATION := "res://supabase/migrations/20261108210000_name_filter.sql"


func test_bad_names_are_refused() -> void:
	for bad in [
		"fuck",
		"FuckYou",
		"fuuuuck",
		"f.u.c.k",
		"sh1t_head",
		"b1tch99",
		"ass",
		"big_ass",
		"4ss.king",
		"Kanker123",
		"klootzak",
		"tyfus.boy",
		"lul",
	]:
		assert_false(NameFilter.is_allowed(bad), "%s is refused" % bad)
		assert_ne(PlayerName.problem(bad), "", "%s shows a problem" % bad)


func test_normal_names_pass() -> void:
	for ok in [
		"buzzybee",
		"classic",
		"bassist",
		"Cocktail",
		"peacock",
		"grape",
		"analyst",
		"Mattis",
		"Dickens",
		"Sussex",
		"Noor",
		"TapTapLeo",
		"mia.flaps",
		"ZippyFlap42",
		"SwiftDash17",
		"Dash1999",
	]:
		assert_true(NameFilter.is_allowed(ok), "%s is fine" % ok)


func test_problem_text_for_a_bad_name() -> void:
	assert_eq(PlayerName.problem("shithead"), "That name isn't allowed. Pick another one.")


## Every dice suggestion passes the filter.
func test_suggestions_are_clean() -> void:
	var rng := RandomNumberGenerator.new()
	for i in 300:
		rng.seed = i
		var n := PlayerName.suggest(rng)
		assert_true(NameFilter.is_allowed(n), "suggestion %s is clean" % n)


## The game warns with the same starter list the database enforces.
func test_game_list_matches_the_database_migration() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_false(sql.is_empty(), "the migration is readable")
	var re := RegEx.new()
	re.compile("\\('([a-z]+)', (true|false)\\)")
	var anywhere: Array[String] = []
	var whole: Array[String] = []
	for m in re.search_all(sql):
		if m.get_string(2) == "true":
			whole.append(m.get_string(1))
		else:
			anywhere.append(m.get_string(1))
	assert_eq(anywhere, NameFilter.ANYWHERE, "words found anywhere")
	assert_eq(whole, NameFilter.WHOLE, "whole words")
