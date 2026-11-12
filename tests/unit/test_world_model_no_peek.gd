extends TestCase
## The FastSim world model (tools/fastsim/World/, docs/WORLD_MODEL.md) plays
## from the present state only: it reads the sim once per tick and moves its
## own copy by the hazards' known motion rules. It must never copy or step the
## sim, read the sim's RNG, call the hazard hooks the sim runs at a bounce, or
## read fields that hold a hidden random choice. This scans its source (the
## same rules as `fastsim world nopeek`, WorldCheck.FORBIDDEN).

const WORLD_DIR := "res://tools/fastsim/World"

const FORBIDDEN := {
	"copies the sim": "\\bclone_deep\\b",
	"runs the sim or a hazard": "\\.step\\s*\\(",
	"runs room steps": "\\.steps_this_tick\\s*\\(",
	"reads the RNG": "\\b(SimRng|_rng|next_u32|next_below|reseed)\\b",
	"reads a hidden salt": "\\.salt\\b",
	"reads a hidden target": "\\.(target_y|next_x)\\b",
	"reads a boss draw": "\\.seed\\b|\\.(draw|lit_rows|slam_of|_next_lane|hop_to|_pick_column|safe_y)\\s*\\(",
	"runs hazard hooks":
	(
		"\\.(setup|_place|on_bounce|on_flap|on_wall_bounce|adjust_wall|near_row|touch|kills"
		+ "|_next_drop|_pick_y|_aim|_load|pop)\\s*\\("
	),
	"runs arrival checks":
	"\\b(ArrivalCheck|_arrival_retries|_arrive_in|_go_through|_enter_room)\\b",
	"changes the sim": "\\bsim\\.(state|room)\\.[a-z_]+\\s*(=[^=]|\\+=|-=|\\+\\+|--)",
}


func test_world_model_never_peeks_at_the_future() -> void:
	assert_true(DirAccess.dir_exists_absolute(WORLD_DIR), "tools/fastsim/World exists")
	var files := DirAccess.get_files_at(WORLD_DIR)
	var scanned := 0
	for file in files:
		if not file.ends_with(".cs"):
			continue
		scanned += 1
		var path := WORLD_DIR.path_join(file)
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i]
			var c := code.find("//")
			if c >= 0:
				code = code.substr(0, c)
			for rule: String in FORBIDDEN:
				var re := RegEx.create_from_string(FORBIDDEN[rule])
				if re.search(code) != null:
					fail("%s:%d %s -> %s" % [path, i + 1, rule, lines[i].strip_edges()])
	assert_true(scanned >= 5, "found the world model's C# files")


func test_the_scan_catches_a_peek() -> void:
	var re := RegEx.create_from_string(FORBIDDEN["copies the sim"])
	assert_true(re.search("var c = sim.clone_deep();") != null, "clone_deep is caught")
	re = RegEx.create_from_string(FORBIDDEN["runs the sim or a hazard"])
	assert_true(re.search("c.step(true);") != null, "step is caught")
	assert_true(re.search("h.Step(w);") == null, "the model's own Step is allowed")
	re = RegEx.create_from_string(FORBIDDEN["reads the RNG"])
	assert_true(re.search("long x = sim._rng.next_below(4);") != null, "the RNG is caught")


## The C# check and this test hold the same rules.
func test_rules_match_the_fastsim_copy() -> void:
	var cs := FileAccess.get_file_as_string("res://tools/fastsim/WorldCheck.cs")
	for rule: String in FORBIDDEN:
		assert_true(cs.contains('("%s", @"' % rule), "WorldCheck.cs has the rule '%s'" % rule)
