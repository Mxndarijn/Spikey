extends TestCase
## The wake-up trigger on new runs (from the Supabase days, when it started
## the GitHub checker; on our server net.http_post only writes it down): a failed
## wake-up must never stop a run from being saved, and the game can't call it.

const MIGRATION := "res://backend/migrations/20261109210000_wake_checker.sql"


func test_wake_up_is_locked_and_never_blocks_a_run() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("exception when others then"), "a failed request is swallowed")
	assert_true(sql.contains("after insert on public.runs"), "fires on new runs")
	assert_true(
		sql.contains("alter table public.worker_settings enable row level security"),
		"the token table is locked"
	)
	for fn in ["worker_set_wake(text, text)", "spikey_wake_checker()"]:
		assert_true(
			sql.contains("revoke all on function public.%s from public, anon, authenticated" % fn),
			"%s is not callable by the game" % fn
		)
