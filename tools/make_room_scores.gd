extends SceneTree
## Bakes the rooms' measured difficulty scores into game/rooms/room_scores.gd,
## the numbers the Rooms screen's room page shows ("Score 46"):
##   godot --headless --path . -s res://tools/make_room_scores.gd --
##     <report.json>... [--set <id>=<score>]... [--none <id,id>] [--stale <id,id>]
##     [--source <text>]
## Each report.json comes from `tools/fastsim.ps1 -Mode difficulty -Step score`
## (docs/ROOM_DIFFICULTY.md). With several, a later file wins for every variant
## it scored, so a rerun of a few rooms goes after the full run. A room's score
## is the mean over its variants in today's catalog (variants and rooms no
## longer in it are left out). `--source` says where the numbers come from
## (the run, its commit); it is written at the top of the file. `--set` gives a
## room a number by hand, over any report's (a room no report scored, or one
## the bots can't measure yet); say where it comes from in `--source`. `--none`
## lists rooms that get no number at all (no bot can play them: the page shows
## "—"). `--stale` marks rooms changed since the run: their entry gets a
## comment saying so, until a new run measures them.

const OUT := "res://game/rooms/room_scores.gd"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source := ""
	var paths: Array[String] = []
	var manual := {}
	var none: Array[String] = []
	var stale: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--source" and i + 1 < args.size():
			source = args[i + 1]
			i += 2
			continue
		if args[i] == "--set" and i + 1 < args.size():
			var kv := args[i + 1].split("=")
			manual[kv[0]] = int(kv[1])
			i += 2
			continue
		if args[i] in ["--none", "--stale"] and i + 1 < args.size():
			var ids := Array(args[i + 1].split(",", false))
			(none if args[i] == "--none" else stale).append_array(ids)
			i += 2
			continue
		paths.append(args[i])
		i += 1
	if paths.is_empty():
		push_error("give one or more report.json files")
		quit(1)
		return
	var by_label := {}
	for path in paths:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not (data as Dictionary).has("rooms"):
			push_error("%s is not a difficulty report.json" % path)
			quit(1)
			return
		for room: Dictionary in data["rooms"]:
			if room.get("score") != null:
				by_label[room["label"]] = float(room["score"])
	var scores := means(by_label)
	for id: String in manual:
		if RoomCatalog.find(id) != null:
			scores[id] = manual[id]
	for id in none:
		scores.erase(id)
	if source.is_empty():
		source = ", ".join(paths)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(render(scores, source, none, stale))
	f.close()
	print("%s: %d rooms" % [OUT, scores.size()])
	for def in RoomCatalog.all():
		if not scores.has(def.id) and def.id not in none:
			print("  no score for %s" % def.id)
	quit(0)


## Room id -> its rounded mean score over today's variants that have one.
static func means(by_label: Dictionary) -> Dictionary:
	var out := {}
	for def in RoomCatalog.all():
		var labels: Array[String] = []
		if def.variants.is_empty():
			labels.append(def.id)
		for v in def.variants:
			labels.append("%s/%s" % [def.id, v.id])
		var sum := 0.0
		var n := 0
		for label in labels:
			if by_label.has(label):
				sum += by_label[label]
				n += 1
		if n > 0:
			out[def.id] = roundi(sum / n)
	return out


## `text` as "## " comment lines of at most `width` characters of text.
static func comment_lines(text: String, width: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		if not line.is_empty() and line.length() + 1 + word.length() > width:
			out.append("## " + line)
			line = ""
		line = word if line.is_empty() else line + " " + word
	if not line.is_empty():
		out.append("## " + line)
	return out


## The source of game/rooms/room_scores.gd (gdformat style).
static func render(
	scores: Dictionary, source: String, none: Array[String] = [], stale: Array[String] = []
) -> String:
	var lines: Array[String] = [
		"class_name RoomScores",
		"extends RefCounted",
		"## Each room's measured difficulty score, the mean over its variants (fastsim",
		"## difficulty, docs/ROOM_DIFFICULTY.md: 20 a beginner, 40 a normal and 60 a",
		"## good player clears it 9 times in 10). Made by tools/make_room_scores.gd;",
		"## don't edit by hand, run the tool on a new difficulty report instead.",
		"##",
	]
	lines.append_array(comment_lines("Source: " + source, 76))
	lines.append_array(["", "const SCORES := {"])
	for def in RoomCatalog.all():
		if scores.has(def.id):
			var entry := '\t"%s": %d,' % [def.id, scores[def.id]]
			if def.id in stale:
				entry += "  # changed since the run: measure again"
			lines.append(entry)
	lines.append("}")
	lines.append("")
	lines.append("## Rooms no bot can measure (the page shows no number).")
	var quoted: Array[String] = []
	for id in none:
		quoted.append('"%s"' % id)
	lines.append("const UNMEASURED: Array[String] = [%s]" % ", ".join(quoted))
	(
		lines
		. append_array(
			[
				"",
				"",
				"## The room's score, or -1 when it has none (not measured, or an id",
				"## that is no longer in the catalog).",
				"static func of(id: String) -> int:",
				"\treturn SCORES.get(id, -1)",
				"",
			]
		)
	)
	return "\n".join(lines)
