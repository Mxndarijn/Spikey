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
	var dir := DirAccess.open(SIM_DIR)
	assert_true(dir != null, "sim/ exists")
	if dir == null:
		return
	var checked := 0
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		checked += 1
		var path := SIM_DIR.path_join(file)
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _strip_comment(lines[i])
			for rule: String in FORBIDDEN:
				var re := RegEx.create_from_string(FORBIDDEN[rule])
				if re.search(code) != null:
					fail("%s:%d %s -> %s" % [file, i + 1, rule, lines[i].strip_edges()])
	assert_true(checked > 0, "found sim scripts")


static func _strip_comment(line: String) -> String:
	var in_string := false
	for i in line.length():
		var ch := line[i]
		if ch == '"':
			in_string = not in_string
		elif ch == "#" and not in_string:
			return line.substr(0, i)
	return line
