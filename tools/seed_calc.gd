extends SceneTree
## Seed calculator: turns (random part, season, version) into a seed code and
## back (meta/seed_code.gd).
##   godot --headless --path . -s res://tools/seed_calc.gd -- 3392377610 halloween 21
##   godot --headless --path . -s res://tools/seed_calc.gd -- K7Q2M-9XH4D
## Season: none, halloween, winter, valentine, spring, summer, newyear, or
## today (the default, from this PC's date). Version: the build's when left out.

const SEASON_NAMES := {
	"none": Seasons.NONE,
	"halloween": Seasons.HALLOWEEN,
	"winter": Seasons.WINTER,
	"valentine": Seasons.VALENTINE,
	"spring": Seasons.SPRING,
	"summer": Seasons.SUMMER,
	"newyear": Seasons.NEW_YEAR,
}


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if args.is_empty():
		printerr("Usage: -- <random> [season] [version]   or   -- <code>")
		return 2
	if not args[0].is_valid_int():
		return _decode(" ".join(args))
	var random := args[0].to_int()
	var season := SeasonCalendar.today()
	if args.size() > 1:
		var name := args[1].to_lower().replace("_", "").replace("'s", "").replace(" ", "")
		if not SEASON_NAMES.has(name) and name != "today":
			printerr("Unknown season: %s (%s, today)" % [args[1], ", ".join(SEASON_NAMES.keys())])
			return 2
		season = SEASON_NAMES.get(name, season)
	var version := SimConfig.GAMEPLAY_VERSION
	if args.size() > 2:
		version = args[2].trim_prefix("v").to_int()
	var code := SeedCode.encode(random, season, version)
	if code.is_empty():
		printerr(
			(
				"Out of range: random 0..%d, version 0..%d"
				% [SeedCode.MAX_RANDOM, SeedCode.MAX_VERSION]
			)
		)
		return 1
	print(code)
	_print_parts(SeedCode.decode(code))
	return 0


## A code (or the whole game over line) back into its parts.
func _decode(text: String) -> int:
	var parts := SeedCode.decode(text)
	if parts == null:
		printerr(SeedCode.problem(text))
		return 1
	_print_parts(parts)
	return 0


func _print_parts(parts: SeedCode.Parts) -> void:
	if parts.legacy:
		print("old seed number (no season)")
	print("random  %d" % parts.random)
	print("season  %s" % _season_name(parts.season))
	print("version %s" % (str(parts.version) if parts.version >= 0 else "unknown"))
	if parts.version >= 0 and parts.version != SimConfig.GAMEPLAY_VERSION:
		print("note    this build plays v%d: the map will differ" % SimConfig.GAMEPLAY_VERSION)


func _season_name(season: int) -> String:
	for name: String in SEASON_NAMES:
		if SEASON_NAMES[name] == season:
			return name
	return str(season)
