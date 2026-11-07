extends SceneTree
## Minimal headless test runner (no addon needed).
##   godot --headless --path . -s res://tests/run_tests.gd [-- <filter>]
## Runs every test_* method in res://tests/**/test_*.gd. A test fails on a
## failed assertion or on any engine/script error logged while it runs.
## Exit code 0 = all passed.


class ErrorCounter:
	extends Logger
	var count := 0
	var last := ""

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = (
			"%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function]
		)


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if args.size() > 0 else ""

	var files := _find_tests("res://tests")
	var passed := 0
	var failed: Array[String] = []
	var start := Time.get_ticks_msec()

	for path in files:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed.append("%s: could not load script" % path)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			if not filter.is_empty() and not (path + ":" + test_name).contains(filter):
				continue
			var instance: TestCase = script.new()
			var errors_before := counter.count
			instance.call(test_name)
			var label := "%s:%s" % [path.get_file().get_basename(), test_name]
			if counter.count > errors_before:
				instance.failures.append("error logged: " + counter.last)
			if instance.failures.is_empty():
				passed += 1
			else:
				failed.append("%s\n      %s" % [label, "\n      ".join(instance.failures)])

	var ms := Time.get_ticks_msec() - start
	for f in failed:
		printerr("  FAIL ", f)
	print("Tests: %d passed, %d failed (%d ms)" % [passed, failed.size(), ms])
	quit(0 if failed.is_empty() and passed > 0 else 1)


func _find_tests(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	out.sort()
	return out
