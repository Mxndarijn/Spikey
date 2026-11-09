extends TestCase
## The database wakes the checker when a run arrives: the migration and the
## workflow it starts have to agree on names, and a failed wake-up must never
## stop a run from being saved.

const MIGRATION := "res://supabase/migrations/20261109210000_wake_checker.sql"
const WORKFLOW := "res://.github/workflows/verify-runs.yml"


func test_migration_starts_the_workflow_that_exists() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	var yml := FileAccess.get_file_as_string(WORKFLOW)
	assert_true(sql.contains("/actions/workflows/verify-runs.yml/dispatches"), "dispatch URL")
	assert_true(yml.contains("workflow_dispatch:"), "the workflow can be started from outside")
	assert_true(yml.contains("schedule:"), "the schedule stays as a safety net")


func test_workflow_stores_the_token_the_migration_reads() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	var yml := FileAccess.get_file_as_string(WORKFLOW)
	assert_true(sql.contains("function public.worker_set_wake(p_token text, p_repo text)"))
	assert_true(yml.contains("public.worker_set_wake(:'token', :'repo')"), "workflow stores it")
	assert_true(yml.contains("secrets.VERIFY_DISPATCH_TOKEN"), "from the GitHub secret")


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
