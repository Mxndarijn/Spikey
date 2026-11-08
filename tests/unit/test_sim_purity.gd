extends TestCase
## Enforces the sim/ rules from docs/ARCHITECTURE.md by scanning the source.
## sim/ must stay deterministic: integers only, no engine time, no Nodes,
## no built-in randomness.

const SIM_DIR := "res://sim"

const FORBIDDEN := {
	"float type": "\\bfloat\\b",
	"float literal": "(?<![\\w.])\\d+\\.\\d+",
	"Vector types": "\\bVector[234]i?\\b",
	"built-in random":
	"\\b(randf|randi|randf_range|randi_range|randomize|seed|RandomNumberGenerator)\\s*\\(",
	"engine time/OS": "\\b(Time|OS|Engine|Performance)\\.",
	"frame delta": "\\bdelta\\b",
	"float math": "\\b(sin|cos|tan|atan2?|sqrt|pow|exp|log|lerp|lerpf)\\s*\\(",
	"Node usage": "\\b(extends\\s+Node\\w*|get_tree|get_node)\\b",
	"cosmetic data": "\\b(Theme|Character|Skin|Palette)\\w*\\.",
}


func test_sim_has_no_forbidden_constructs() -> void:
	assert_true(DirAccess.dir_exists_absolute(SIM_DIR), "sim/ exists")
	var files := _scripts(SIM_DIR)
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _strip_comment(lines[i])
			for rule: String in FORBIDDEN:
				var re := RegEx.create_from_string(FORBIDDEN[rule])
				if re.search(code) != null:
					fail("%s:%d %s -> %s" % [path, i + 1, rule, lines[i].strip_edges()])
	assert_true(files.size() > 10, "found sim scripts in sim/ and its folders")


## Every .gd under `dir`, including sim/rooms/ and sim/hazards/.
static func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	return out


static func _strip_comment(line: String) -> String:
	var in_string := false
	for i in line.length():
		var ch := line[i]
		if ch == '"':
			in_string = not in_string
		elif ch == "#" and not in_string:
			return line.substr(0, i)
	return line
