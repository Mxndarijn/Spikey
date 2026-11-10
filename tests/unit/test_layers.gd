extends TestCase
## Enforces the layer order from docs/ARCHITECTURE.md by scanning the source:
## each folder may use classes from the folders before it, never after.
##   sim -> meta -> services -> game
## server/ replays runs with sim/ and the season rules in meta/ only.

const LAYERS: Array[String] = ["sim", "meta", "services", "game"]
## Folders outside the chain and the layers they may use.
const EXTRA := {"server": ["sim", "meta", "server"]}

const CLASS_RE := "(?m)^class_name\\s+(\\w+)"


func test_no_folder_uses_a_later_layer() -> void:
	var owner := _class_owners()
	assert_true(owner.size() > 50, "found the project's classes")
	var allowed := {}
	for i in LAYERS.size():
		allowed[LAYERS[i]] = LAYERS.slice(0, i + 1)
	allowed.merge(EXTRA)
	var word := RegEx.create_from_string("\\b[A-Z]\\w*\\b")
	for folder: String in allowed:
		for path in _scripts("res://" + folder):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var code := _strip(lines[i])
				for m in word.search_all(code):
					var name := m.get_string()
					if not owner.has(name):
						continue
					var layer: String = owner[name]
					if layer not in allowed[folder]:
						fail("%s:%d uses %s from %s/" % [path, i + 1, name, layer])


## class_name -> the top folder it lives in.
static func _class_owners() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string(CLASS_RE)
	for folder: String in LAYERS + EXTRA.keys():
		for path in _scripts("res://" + folder):
			var m := re.search(FileAccess.get_file_as_string(path))
			if m != null:
				out[m.get_string(1)] = folder
	return out


static func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


## The line without its comment and string literals.
static func _strip(line: String) -> String:
	var out := ""
	var quote := ""
	for c in line:
		if quote.is_empty():
			if c == "#":
				break
			if c == '"' or c == "'":
				quote = c
				continue
			out += c
		elif c == quote:
			quote = ""
	return out
