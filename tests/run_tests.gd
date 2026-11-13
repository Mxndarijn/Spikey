extends SceneTree
## Minimal headless test runner (no addon needed).
##   godot --headless --path . -s res://tests/run_tests.gd [-- [filter] [--jobs N]
##     [--only a,b] [--skip c,d]]
## Runs every test_* method in res://tests/**/test_*.gd. A test fails on a
## failed assertion or on any engine/script error logged while it runs.
## Exit code 0 = all passed.
##
## With --jobs N (N > 1) it starts N headless copies of itself ("workers") that
## share the work. Each piece of work is claimed by making a folder, which only
## one process can do, so a free worker always takes the next piece. A piece is:
## - a whole test file, by default (its tests may share a save file);
## - one test method, in a file with `const PARALLEL := true`;
## - one part of a method `test_x(part: int, parts: int)`, in a file with
##   `const PARTS := n`: the method runs n times, part 0..n-1, each doing its
##   share. It may put a Dictionary in `report`; once every part ran, the file's
##   `static func combine_test_x(reports: Array) -> Array[String]` gets them all
##   and returns failures (for checks over the whole, like a total).
## Pieces start longest first, by the times of the last run (user://test_times.json).
## --only keeps the test files whose path contains one of its comma-separated
## parts, --skip drops them (tools/check.ps1 uses both to run one test tier).


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


## One piece of work: a file, a method in it, or one part of a method.
class Unit:
	var path := ""
	## Empty: every test in the file.
	var method := ""
	var part := -1
	var parts := 0

	func key() -> String:
		var out := path
		if not method.is_empty():
			out += ":" + method
		if part >= 0:
			out += "#%d" % part
		return out

	## A name that can be a folder name.
	func folder() -> String:
		return key().trim_prefix("res://").replace("/", "_").replace(":", "-").replace("#", "_p")


const TIMES_PATH := "user://test_times.json"

var _started := false
var _counter := ErrorCounter.new()
var _filter := ""
var _only: PackedStringArray = []
var _skip: PackedStringArray = []
var _passed := 0
var _failed: Array[String] = []
## Combine key ("path:method") -> reports of its parts.
var _reports := {}
## Unit key -> ms it took.
var _times := {}


## Tests run on the first frame, once the scene tree is live, so nodes added to
## the root get their _ready() like in the game.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_main()
	return false


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs := 1
	var worker_dir := ""
	var i := 0
	while i < args.size():
		match args[i]:
			"--jobs":
				i += 1
				jobs = int(args[i])
			"--worker":
				i += 1
				worker_dir = args[i]
			"--only":
				i += 1
				_only = args[i].split(",", false)
			"--skip":
				i += 1
				_skip = args[i].split(",", false)
			_:
				_filter = args[i]
		i += 1
	if not worker_dir.is_empty():
		await _work(worker_dir)
	elif jobs > 1:
		await _lead(jobs)
	else:
		await _run_alone()


## Everything in this process, one test after another.
func _run_alone() -> void:
	OS.add_logger(_counter)
	var start := Time.get_ticks_msec()
	for unit in _units():
		await _run_unit(unit)
	_combine()
	_finish(Time.get_ticks_msec() - start)


## A worker: claims pieces in `dir` until none is left, then writes its report.
func _work(dir: String) -> void:
	OS.add_logger(_counter)
	var me := str(OS.get_process_id())
	var done: Array[String] = []
	for unit in _units():
		if DirAccess.make_dir_absolute(dir.path_join(unit.folder())) != OK:
			continue
		var running := FileAccess.open(dir.path_join("running_%s.txt" % me), FileAccess.WRITE)
		running.store_string(unit.key())
		running.close()
		await _run_unit(unit)
		done.append(unit.key())
	var report := {
		"passed": _passed, "failed": _failed, "reports": _reports, "times": _times, "done": done
	}
	var out := FileAccess.open(dir.path_join("report_%s.json" % me), FileAccess.WRITE)
	out.store_string(JSON.stringify(report))
	out.close()
	quit(0)


## Starts `jobs` workers, waits for them, and adds up what they found.
func _lead(jobs: int) -> void:
	var start := Time.get_ticks_msec()
	var dir := OS.get_user_data_dir().path_join("test_run_%d" % OS.get_process_id())
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var units := _units()
	var pids: Array[int] = []
	for k in mini(jobs, units.size()):
		var args := PackedStringArray(
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--log-file",
				dir.path_join("worker_%d.log" % k),
				"-s",
				"res://tests/run_tests.gd",
				"--",
				"--worker",
				dir,
			]
		)
		if not _filter.is_empty():
			args.append(_filter)
		if not _only.is_empty():
			args.append_array(["--only", ",".join(_only)])
		if not _skip.is_empty():
			args.append_array(["--skip", ",".join(_skip)])
		pids.append(OS.create_process(OS.get_executable_path(), args))
	var waiting := true
	while waiting:
		await create_timer(0.05).timeout
		waiting = false
		for pid in pids:
			waiting = waiting or OS.is_process_running(pid)

	var done := {}
	for pid in pids:
		var path := dir.path_join("report_%d.json" % pid)
		var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if report is not Dictionary or OS.get_process_exit_code(pid) != 0:
			var running := FileAccess.get_file_as_string(dir.path_join("running_%d.txt" % pid))
			_failed.append("worker %d crashed while running %s" % [pid, running])
			continue
		_passed += int(report.passed)
		for f: String in report.failed:
			_failed.append(f)
		for key: String in report.reports:
			if not _reports.has(key):
				_reports[key] = []
			_reports[key].append_array(report.reports[key])
		_times.merge(report.times)
		for key: String in report.done:
			done[key] = true
	for unit in units:
		if not done.has(unit.key()) and _failed.is_empty():
			_failed.append("%s: never ran" % unit.key())
	_combine()
	if _failed.is_empty():
		_remove_tree(dir)
	else:
		print("Worker logs: ", dir)
	_print_slowest()
	_finish(Time.get_ticks_msec() - start)


## Runs one piece and counts its tests.
func _run_unit(unit: Unit) -> void:
	var start := Time.get_ticks_msec()
	var script := load(unit.path) as GDScript
	if script == null or not script.can_instantiate():
		_failed.append("%s: could not load script" % unit.path)
		return
	for method in script.get_script_method_list():
		var test_name: String = method.name
		if not test_name.begins_with("test_"):
			continue
		if not unit.method.is_empty() and test_name != unit.method:
			continue
		if not _wanted(unit.path, test_name):
			continue
		# Each part of a method is a piece of its own (see _units).
		if method.args.size() == 2:
			if unit.part >= 0:
				await _run_test(script, unit.path, test_name, unit.part, unit.parts)
		else:
			await _run_test(script, unit.path, test_name, -1, 0)
	_times[unit.key()] = Time.get_ticks_msec() - start


func _run_test(script: GDScript, path: String, test_name: String, part: int, parts: int) -> void:
	var instance: TestCase = script.new()
	var errors_before := _counter.count
	# Awaiting lets a test wait for frames (e.g. to run _draw); plain tests return at once.
	if part >= 0:
		await instance.call(test_name, part, parts)
	else:
		await instance.call(test_name)
	var label := "%s:%s" % [path.get_file().get_basename(), test_name]
	if part >= 0:
		label += " part %d of %d" % [part + 1, parts]
		var key := "%s:%s" % [path, test_name]
		if not _reports.has(key):
			_reports[key] = []
		_reports[key].append(instance.report)
	if _counter.count > errors_before:
		instance.failures.append("error logged: " + _counter.last)
	if instance.failures.is_empty():
		_passed += 1
	else:
		_failed.append("%s\n      %s" % [label, "\n      ".join(instance.failures)])


## The checks over every part of a method, once all parts ran.
func _combine() -> void:
	var keys := _reports.keys()
	keys.sort()
	for key: String in keys:
		var path := key.get_slice(":", 0) + ":" + key.get_slice(":", 1)
		var test_name := key.get_slice(":", 2)
		var script := load(path) as GDScript
		var combine := "combine_" + test_name
		if not script.has_method(combine):
			continue
		var reports: Array = _reports[key]
		var failures: Array[String] = script.call(combine, reports)
		var label := "%s:%s (all parts)" % [path.get_file().get_basename(), test_name]
		if failures.is_empty():
			_passed += 1
		else:
			_failed.append("%s\n      %s" % [label, "\n      ".join(failures)])


func _finish(ms: int) -> void:
	for f in _failed:
		printerr("  FAIL ", f)
	print("Tests: %d passed, %d failed (%d ms)" % [_passed, _failed.size(), ms])
	if _failed.is_empty() and _filter.is_empty() and _only.is_empty() and _skip.is_empty():
		var out := FileAccess.open(TIMES_PATH, FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify(_times))
			out.close()
	quit(0 if _failed.is_empty() and _passed > 0 else 1)


func _print_slowest() -> void:
	var keys := _times.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _times[a] > _times[b])
	var lines: Array[String] = []
	for key: String in keys.slice(0, 5):
		lines.append("%s %.1f s" % [key.trim_prefix("res://tests/"), _times[key] / 1000.0])
	print("Slowest: ", ", ".join(lines))


func _wanted(path: String, test_name: String) -> bool:
	return _filter.is_empty() or (path + ":" + test_name).contains(_filter)


## Whether the file is in the tier asked for (--only, --skip).
func _picked(path: String) -> bool:
	for part in _skip:
		if path.contains(part):
			return false
	if _only.is_empty():
		return true
	for part in _only:
		if path.contains(part):
			return true
	return false


## Every piece of work, longest first by the last run's times.
func _units() -> Array[Unit]:
	var out: Array[Unit] = []
	for path in _find_tests("res://tests"):
		if not _picked(path):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			var broken := Unit.new()
			broken.path = path
			out.append(broken)
			continue
		var consts := script.get_script_constant_map()
		var whole := Unit.new()
		whole.path = path
		var any := false
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_") or not _wanted(path, test_name):
				continue
			any = true
			if method.args.size() == 2:
				var parts: int = consts.get("PARTS", 1)
				for p in parts:
					var u := Unit.new()
					u.path = path
					u.method = test_name
					u.part = p
					u.parts = parts
					out.append(u)
			elif consts.get("PARALLEL", false):
				var u := Unit.new()
				u.path = path
				u.method = test_name
				out.append(u)
		if any and not consts.get("PARALLEL", false):
			out.append(whole)
	var times := {}
	if FileAccess.file_exists(TIMES_PATH):
		var last: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIMES_PATH))
		if last is Dictionary:
			times = last
	# Unknown pieces first: they may be slow, and a quick one costs little.
	out.sort_custom(
		func(a: Unit, b: Unit) -> bool: return times.get(a.key(), 1e9) > times.get(b.key(), 1e9)
	)
	return out


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


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
