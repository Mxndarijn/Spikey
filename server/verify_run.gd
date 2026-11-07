extends SceneTree
## Headless run verifier: the anti-cheat core of the leaderboards.
##   godot --headless --path . -s res://server/verify_run.gd -- run.json
## Prints one JSON line {ok, reason, score, end_tick, checksum}; exit 0 = accepted.
## Seed issuing/expiry, plausibility checks and device attestation wrap around
## this in the Phase 3 server.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -s res://server/verify_run.gd -- <run.json>")
		quit(2)
		return
	var text := FileAccess.get_file_as_string(args[0])
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		print(JSON.stringify({"ok": false, "reason": "invalid JSON"}))
		quit(1)
		return
	var result := Replay.from_dict(data).verify()
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
