extends TestCase
## The design kit's rules, checked for every world, including future paid and
## seasonal ones: all world tokens present, hazards readable on every sky
## stop, UI text readable, and generated files in sync with data/design/.

const MIN_HAZARD := 3.0
const MIN_TEXT := 4.5
const IMPORTER := "res://tools/import_design_kit.gd"
const TOKENS := "res://data/design/tokens.json"
const PALETTES := "res://data/design/room_palettes.json"
const EXTRA := "res://data/design/extra_worlds.json"


func test_catalog_has_the_launch_worlds() -> void:
	var ids: Array[String] = []
	for t in ThemeCatalog.all():
		ids.append(t.id)
	for id in ["sunset", "jungle", "ice", "lava", "deepsea", "sugar", "star"]:
		assert_true(id in ids, "world %s exists" % id)
	assert_eq(ThemeCatalog.default_theme().id, ThemeCatalog.DEFAULT_ID)


func test_every_world_is_complete() -> void:
	for t in ThemeCatalog.all():
		assert_false(t.id.is_empty(), "world has an id")
		assert_false(t.display_name.is_empty(), "%s has a name" % t.id)
		for token_name in ThemeDef.WORLD_TOKENS:
			assert_eq(t.token(token_name).a, 1.0, "%s %s is opaque" % [t.id, token_name])


func test_spikes_readable_on_every_sky_stop() -> void:
	for t in ThemeCatalog.all():
		for stop in t.all_sky_stops():
			var r := Contrast.ratio(t.spike, stop)
			assert_true(
				r >= MIN_HAZARD,
				(
					"%s: spike %s on sky %s is %.2f:1, needs %.1f:1"
					% [t.id, t.spike.to_html(false), stop.to_html(false), r, MIN_HAZARD]
				)
			)


func test_ui_text_readable() -> void:
	var pairs := [
		["on-panel / panel", UiTokens.ON_PANEL, UiTokens.PANEL],
		["on-panel / panel-raised", UiTokens.ON_PANEL, UiTokens.PANEL_RAISED],
		["on-panel-muted / panel", UiTokens.ON_PANEL_MUTED, UiTokens.PANEL],
		["on-panel-muted / panel-raised", UiTokens.ON_PANEL_MUTED, UiTokens.PANEL_RAISED],
		["on-action / action", UiTokens.ON_ACTION, UiTokens.ACTION],
		["coin / panel", UiTokens.COIN, UiTokens.PANEL],
		["success / panel", UiTokens.SUCCESS, UiTokens.PANEL],
		["danger / panel", UiTokens.DANGER, UiTokens.PANEL],
	]
	for p: Array in pairs:
		var r := Contrast.ratio(p[1], p[2])
		assert_true(r >= MIN_TEXT, "%s is %.2f:1, needs %.1f:1" % [p[0], r, MIN_TEXT])


func test_generated_files_match_design_data() -> void:
	var hint := " (run tools/import_design_kit.gd)"
	var importer: GDScript = load(IMPORTER)
	var tokens: Dictionary = _json(TOKENS)
	var palettes: Dictionary = _json(PALETTES)
	var extra: Dictionary = _json(EXTRA)
	var worlds: Array[Dictionary] = importer.collect_worlds(tokens, extra.get("worlds", []))
	assert_eq(ThemeCatalog.all().size(), worlds.size(), "number of worlds" + hint)
	for i in worlds.size():
		var want: ThemeDef = importer.build_theme(worlds[i], i, palettes)
		var have := ThemeCatalog.find(want.id)
		if have == null:
			fail("missing data/themes/%s.tres%s" % [want.id, hint])
			continue
		for token_name in ThemeDef.WORLD_TOKENS:
			assert_eq(
				have.token(token_name).to_html(),
				want.token(token_name).to_html(),
				"%s %s%s" % [want.id, token_name, hint]
			)
		assert_eq(have.palette_count(), want.palette_count(), "%s palettes%s" % [want.id, hint])
	var consts := (load("res://game/style/ui_tokens.gd") as GDScript).get_script_constant_map()
	for tok: Dictionary in tokens.color.tokens:
		if tok.value is String:
			var key := (tok.name as String).to_upper().replace("-", "_")
			assert_true(consts.has(key), "UiTokens.%s exists%s" % [key, hint])
			if consts.has(key):
				assert_eq(
					(consts[key] as Color).to_html(),
					Color(tok.value).to_html(),
					"UiTokens.%s%s" % [key, hint]
				)


static func _json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
