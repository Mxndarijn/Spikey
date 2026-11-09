extends SceneTree
## Checks a batch of stored leaderboard runs (.github/workflows/verify-runs.yml):
##   godot --headless --path . -s res://server/verify_batch.gd -- pending.json results.json
## pending.json: the answer of worker_pending_runs (supabase/migrations/).
## results.json: [{"id", "status", "reason"}, ...] for worker_record_results.
## Runs newer than this checker's sim are left out, so they stay pending.
## Exit 0 = results written (whatever they say), 1 = bad input.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -s res://server/verify_batch.gd -- <pending.json> <results.json>")
		quit(2)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(args[0])) != OK or not json.data is Array:
		printerr("pending runs are not a JSON list")
		quit(1)
		return
	var results: Array[Dictionary] = []
	var counts := {RunChecker.OK: 0, RunChecker.REJECTED: 0, RunChecker.OUTDATED: 0, "skipped": 0}
	for item: Variant in json.data:
		if not item is Dictionary:
			continue
		var result := RunChecker.check(item as Dictionary)
		if result.is_empty():
			counts.skipped += 1
			continue
		results.append(result)
		counts[result.status] += 1
		if result.status != RunChecker.OK:
			print("run %d %s: %s" % [result.id, result.status, result.reason])
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	if f == null:
		printerr("can't write %s" % args[1])
		quit(1)
		return
	f.store_string(JSON.stringify(results))
	f.close()
	print(
		(
			"checked %d runs: %d ok, %d rejected, %d outdated, %d newer than this checker"
			% [results.size(), counts.ok, counts.rejected, counts.outdated, counts.skipped]
		)
	)
	quit(0)
