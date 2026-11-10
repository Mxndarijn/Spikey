extends SceneTree
## Loads every script and scene in the project and fails on any error.
##   godot --headless --path . -s res://tools/ci/load_all.gd

# .claude holds other sessions' git worktrees: full copies of the project.
const SKIP_DIRS: Array[String] = [".godot", ".git", ".claude", "addons", "build", "android"]


class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(
		_function: String,
		_file: String,
		_line: int,
		_code: String,
		_rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var paths: Array[String] = []
	_collect("res://", paths)
	var bad: Array[String] = []
	for path in paths:
		var before := counter.count
		var res := load(path)
		var ok := res != null
		if res is GDScript:
			ok = ok and (res as GDScript).can_instantiate()
		elif res is PackedScene:
			var node := (res as PackedScene).instantiate()
			ok = ok and node != null
			if node != null:
				node.free()
		if not ok or counter.count > before:
			bad.append(path)
	for path in bad:
		printerr("  LOAD FAIL ", path)
	print("Loaded %d files, %d failed" % [paths.size(), bad.size()])
	quit(0 if bad.is_empty() else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub not in SKIP_DIRS:
			_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
