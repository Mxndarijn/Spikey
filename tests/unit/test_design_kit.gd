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
const SCENES := "res://data/design/world_scenes.json"


func test_catalog_has_the_launch_worlds() -> void:
	var ids: Array[String] = []
	for t in ThemeCatalog.all():
		ids.append(t.id)
	for id in ["sunset", "jungle", "ice", "lava", "deepsea", "sugar", "star"]:
		assert_true(id in ids, "world %s exists" % id)
	for id in ["autumn", "desert", "blossom", "neon", "haunted", "winterfest"]:
		assert_true(id in ids, "world %s exists" % id)
	for id in ["meadow", "cove", "clouds", "glade", "aurora", "lantern"]:
		assert_true(id in ids, "world %s exists" % id)
	assert_eq(ThemeCatalog.default_theme().id, ThemeCatalog.DEFAULT_ID)


func test_every_world_is_complete() -> void:
	for t in ThemeCatalog.all():
		assert_false(t.id.is_empty(), "world has an id")
		assert_false(t.display_name.is_empty(), "%s has a name" % t.id)
		for token_name in ThemeDef.WORLD_TOKENS + ThemeDef.SCENE_TOKENS:
			assert_eq(t.token(token_name).a, 1.0, "%s %s is opaque" % [t.id, token_name])
		assert_true(t.sky_split > 0.2 and t.sky_split < 0.9, "%s sky split" % t.id)


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
		["on-panel / edge", UiTokens.ON_PANEL, UiTokens.EDGE],
		["on-primary / primary", UiTokens.ON_PRIMARY, UiTokens.PRIMARY],
		[
			"on-scrim / scrim over a light sky",
			UiTokens.ON_SCRIM,
			_over(UiTokens.SCRIM, Color.WHITE)
		],
		["on-panel-muted / panel", UiTokens.ON_PANEL_MUTED, UiTokens.PANEL],
		["on-panel-muted / panel-raised", UiTokens.ON_PANEL_MUTED, UiTokens.PANEL_RAISED],
		["on-action / action", UiTokens.ON_ACTION, UiTokens.ACTION],
		["on-panel / coin pill", UiTokens.ON_PANEL, UiTokens.COIN],
		["on-panel / success", UiTokens.ON_PANEL, UiTokens.SUCCESS],
		["on-panel / selected card", UiTokens.ON_PANEL, UiTheme.SELECTED_FILL],
		["on-panel / disabled button", UiTokens.ON_PANEL, UiTheme.DISABLED_FILL],
		["danger / panel", UiTokens.DANGER, UiTokens.PANEL],
	]
	for p: Array in pairs:
		var r := Contrast.ratio(p[1], p[2])
		assert_true(r >= MIN_TEXT, "%s is %.2f:1, needs %.1f:1" % [p[0], r, MIN_TEXT])


## The minimal kit: cream paper cards with ink text and no outlines or drops;
## the soft edge colour (tracks, inactive tabs) stays clearly lighter than ink
## and is never used for text.
func test_paper_cards_and_ink_text() -> void:
	assert_ne(UiTokens.PANEL.to_html(false), "ffffff", "cards are cream paper, not white")
	assert_true(UiTokens.PANEL.get_luminance() > 0.9, "paper is light")
	assert_eq(UiTokens.INK_LINE.to_html(false), UiTokens.ON_PANEL.to_html(false), "one ink")
	assert_eq(UiTokens.ON_SKY.to_html(false), UiTokens.ON_PANEL.to_html(false), "ink on the room")
	assert_eq(UiTokens.PRIMARY.to_html(false), UiTokens.ON_PANEL.to_html(false), "ink Play")
	assert_true(Contrast.ratio(UiTokens.ON_PRIMARY, UiTokens.PRIMARY) >= MIN_TEXT, "Play text")
	assert_true(Contrast.ratio(UiTokens.EDGE, UiTokens.PANEL) < 1.6, "the edge is soft")
	assert_true(Contrast.ratio(UiTokens.INK_LINE, UiTokens.EDGE) >= MIN_TEXT, "ink on the edge")
	var tokens: Dictionary = _json(TOKENS)
	for tok: Dictionary in tokens.shadow.tokens:
		assert_eq(tok.name, "focus-ring", "no drop shadow tokens (%s)" % tok.name)
	var t := UiTheme.get_theme()
	for type_name in ["StickerPanel", "Card", "BigPanel", "TabStrip"]:
		var box := t.get_stylebox("panel", type_name) as StyleBoxFlat
		assert_true(box != null, "%s is a flat box" % type_name)
		if box != null:
			assert_eq(box.border_width_top, 0, "%s has no outline" % type_name)
			assert_eq(box.shadow_size, 0, "%s has no drop" % type_name)
	for label_type in ["TitleLabel", "LogoLabel", "SkyLabel", "RoomScore"]:
		assert_eq(t.get_constant("outline_size", label_type), 0, "%s has no outline" % label_type)


## Night rooms get white room text: ink would not read on their sky.
func test_room_text_reads_on_every_world() -> void:
	for w in ThemeCatalog.all():
		var ink := UiTheme.room_ink(w)
		for stop in [w.sky_top, w.sky_mid]:
			var r := Contrast.ratio(ink, stop)
			assert_true(
				r >= UiTheme.ROOM_INK_MIN or UiTheme.is_dark_room(w),
				"%s: room text %.2f:1 on %s" % [w.id, r, stop.to_html(false)]
			)


## Spike colour means danger only: the UI's own fills and text never use it.
func test_ui_never_uses_a_spike_colour() -> void:
	var ui := [
		UiTokens.ON_ACTION,
		UiTokens.ACTION,
		UiTokens.PANEL,
		UiTokens.INK_900,
		UiTokens.INK_LINE,
		UiTokens.PRIMARY,
		UiTokens.EDGE,
		UiTokens.ON_PANEL_MUTED,
	]
	for t in ThemeCatalog.all():
		for c: Color in ui:
			assert_true(
				c.to_html(false) != t.spike.to_html(false),
				"%s spike colour is used by the UI (%s)" % [t.id, c.to_html(false)]
			)


## The ceiling and floor kill all along: their spike rows must be unbroken and
## reach the kill lines, so nothing deadly looks safe.
func test_edge_spikes_cover_the_kill_lines() -> void:
	var reach := RoomView.BAND + RoomView.EDGE_SPIKE_DEPTH
	assert_true(
		reach >= float(SimConfig.KILL_TOP) / SimConfig.SUB, "ceiling spikes reach the kill line"
	)
	var floor_line := float(SimConfig.WORLD_H - SimConfig.KILL_BOTTOM) / SimConfig.SUB
	assert_true(reach >= floor_line, "floor spikes reach the kill line")
	var count := int(RoomView.W / (RoomView.EDGE_SPIKE_HALF * 2.0))
	assert_true(count * RoomView.EDGE_SPIKE_HALF * 2.0 >= RoomView.W - 0.5, "spikes touch")


func test_generated_files_match_design_data() -> void:
	var hint := " (run tools/import_design_kit.gd)"
	var importer: GDScript = load(IMPORTER)
	var tokens: Dictionary = _json(TOKENS)
	var palettes: Dictionary = _json(PALETTES)
	var extra: Dictionary = _json(EXTRA)
	var scenes: Dictionary = _json(SCENES).get("worlds", {})
	var worlds: Array[Dictionary] = importer.collect_worlds(tokens, extra.get("worlds", []))
	assert_eq(ThemeCatalog.all().size(), worlds.size(), "number of worlds" + hint)
	for i in worlds.size():
		var want: ThemeDef = importer.build_theme(worlds[i], i, palettes, scenes)
		assert_true(scenes.has(want.id), "%s has scene colours in world_scenes.json" % want.id)
		var have := ThemeCatalog.find(want.id)
		if have == null:
			fail("missing data/themes/%s.tres%s" % [want.id, hint])
			continue
		for token_name in ThemeDef.WORLD_TOKENS + ThemeDef.SCENE_TOKENS:
			assert_eq(
				have.token(token_name).to_html(),
				want.token(token_name).to_html(),
				"%s %s%s" % [want.id, token_name, hint]
			)
		assert_eq(have.palette_count(), want.palette_count(), "%s palettes%s" % [want.id, hint])
		assert_eq(have.sky_split, want.sky_split, "%s sky split%s" % [want.id, hint])
		assert_eq(have.night, want.night, "%s night%s" % [want.id, hint])
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


## `top` (with alpha) laid over an opaque `under`.
static func _over(top: Color, under: Color) -> Color:
	return Color(under.lerp(Color(top, 1.0), top.a), 1.0)


static func _json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Only spikes may use a world's spike colour, so no other token repeats it.
func test_no_world_token_reuses_the_spike_colour() -> void:
	for t in ThemeCatalog.all():
		for token_name in ThemeDef.WORLD_TOKENS:
			if token_name == "spike":
				continue
			assert_true(
				t.token(token_name).to_html(false) != t.spike.to_html(false),
				"%s: %s is the spike colour" % [t.id, token_name]
			)


## Falling things: every kind moves, and they stay below the score.
func test_falling_things_stay_below_the_score() -> void:
	for id: String in RoomView.MOTE_KIND:
		var kind := RoomView.mote_kind(id)
		assert_true(RoomView.MOTE_MOTION.has(kind), "%s particle kind moves" % id)
		assert_true(RoomView.MOTE_COUNT.get(id, 0) > 0, "%s has particles" % id)
		var band: Vector2 = RoomView.MOTE_BAND[id]
		assert_true(band.x >= RoomView.MOTE_TOP, "%s particles start below the score" % id)
		assert_true(band.y > band.x and band.y < 606.0, "%s particle band is in the room" % id)
	assert_true(RoomView.MOTE_TOP >= WorldScenes.SCORE_ZONE.end.y, "below the score area")
	assert_eq(RoomView.mote_kind("not_a_world"), "", "unknown worlds have none")


## The hill layers sit behind the walls' lowest spikes and the floor row.
func test_spikes_readable_on_every_hill() -> void:
	for t in ThemeCatalog.all():
		for c: Color in [t.hill_far, t.hill_mid, t.hill_near]:
			var r := Contrast.ratio(t.spike, c)
			assert_true(
				r >= MIN_HAZARD,
				(
					"%s: spike on hill %s is %.2f:1, needs %.1f:1"
					% [t.id, c.to_html(false), r, MIN_HAZARD]
				)
			)


## Everything a world's scene draws where spikes sit (ceiling, floor, wall
## slots) keeps the spike at 3:1, in every time of day. See-through shapes are
## checked as they show over the sky.
func test_spikes_readable_on_everything_behind_them() -> void:
	for t in ThemeCatalog.all():
		for room in t.palette_count():
			var pen := _record(t, room)
			for shape: Dictionary in pen.shapes:
				var rect: Rect2 = shape.rect
				var c: Color = shape.color
				if c.a < 0.02 or not WorldScenes.in_spike_zone(rect):
					continue
				var seen := c
				if c.a < 1.0:
					seen = pen.sky_at(rect.get_center().y).lerp(Color(c, 1.0), c.a)
				var r := Contrast.ratio(t.spike, seen)
				assert_true(
					r >= MIN_HAZARD,
					(
						"%s room %d: spike on %s at %s is %.2f:1, needs %.1f:1"
						% [t.id, room, seen.to_html(false), rect, r, MIN_HAZARD]
					)
				)


## The score area stays clear: only the sky, full-width layers and faint
## (under 15% opacity) shapes may cover it. Checked every 5 px, 5 px in from
## its edge (the boards let a sun's rim graze a corner).
func test_scenes_keep_the_score_area_clear() -> void:
	var zone := WorldScenes.SCORE_ZONE.grow(-5.0)
	for t in ThemeCatalog.all():
		for shape: Dictionary in _record(t, 0).shapes:
			var rect: Rect2 = shape.rect
			var c: Color = shape.color
			if rect.size.x >= RoomView.W - 1.0 or c.a < 0.15 or not rect.intersects(zone):
				continue
			var hit := _first_cover(shape, zone)
			if hit.x >= 0.0:
				fail("%s draws %s over the score area at %s" % [t.id, c.to_html(), hit])


static func _first_cover(shape: Dictionary, zone: Rect2) -> Vector2:
	for x in range(int(zone.position.x), int(zone.end.x) + 1, 5):
		for y in range(int(zone.position.y), int(zone.end.y) + 1, 5):
			if ScenePen.covers(shape, Vector2(x, y)):
				return Vector2(x, y)
	return Vector2(-1, -1)


func test_every_world_has_its_own_scene() -> void:
	for t in ThemeCatalog.all():
		assert_true(WorldScenes.has_scene(t.id), "%s has a scene" % t.id)


static func _record(t: ThemeDef, room: int) -> ScenePen:
	var pen := ScenePen.new(null, true)
	pen.sky = t.sky_for_room(room)
	pen.sky_split = t.sky_split
	WorldScenes.paint(pen, t)
	return pen


## Midnight Cage darkens the room night blue (the sky more) but never takes the
## spikes below 3:1; worlds with light spikes get the full tint.
func test_midnight_keeps_spikes_readable() -> void:
	for t in ThemeCatalog.all():
		var dim := WorldScenes.midnight_dim(t)
		assert_true(dim.x >= 0.0 and dim.x <= WorldScenes.MIDNIGHT_MAX, "%s dim" % t.id)
		assert_true(dim.y >= 0.0 and dim.y <= WorldScenes.MIDNIGHT_SKY_MAX, "%s sky dim" % t.id)
		var checks: Array = []
		for c in WorldScenes.colors_behind_spikes(t):
			checks.append(WorldScenes.midnight_color(c, dim.x))
		for c in t.all_sky_stops():
			checks.append(WorldScenes.midnight_color(c, dim.x, dim.y))
		for seen: Color in checks:
			var r := Contrast.ratio(t.spike, seen)
			assert_true(
				r >= MIN_HAZARD,
				"%s midnight: spike on %s is %.2f:1" % [t.id, seen.to_html(false), r]
			)
		if t.night:
			assert_true(
				is_equal_approx(dim.x, WorldScenes.MIDNIGHT_MAX),
				"%s (night) gets the full tint" % t.id
			)
