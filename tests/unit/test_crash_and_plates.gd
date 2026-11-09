extends TestCase
## The two newest cosmetic kinds, crash effects and name plates, plus the flap
## trails: in the catalog, priced, saved, loaded and drawn. Looks only.

const TEST_PATH := "user://test_crash_plates_profile.json"
const FLAP_TRAILS: Array[String] = [
	"cloud_puff",
	"ripple",
	"hearts",
	"feather_drop",
	"splash",
	"snowflake",
	"blossom",
	"paw_prints",
	"flame",
	"zap",
]


func _frames(n: int = 1) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in n:
		await tree.process_frame


func _spikes() -> Dictionary:
	var out := {}
	for t in ThemeCatalog.all():
		out[t.spike.to_html(false)] = t.id
	return out


func test_catalog_lists_both_kinds() -> void:
	assert_true(Catalog.CRASH in Catalog.KINDS and Catalog.PLATE in Catalog.KINDS, "both are kinds")
	assert_eq(Catalog.crashes().size(), 10, "ten crash effects")
	assert_eq(Catalog.plates().size(), 10, "ten name plates")
	assert_eq(Catalog.ids(Catalog.CRASH)[0], CrashStyle.DEFAULT_ID, "the default comes first")
	assert_eq(Catalog.ids(Catalog.PLATE)[0], PlateStyle.DEFAULT_ID, "Paper comes first")
	for kind: String in [Catalog.CRASH, Catalog.PLATE]:
		var seen := {}
		for id in Catalog.ids(kind):
			assert_false(seen.has(id), "%s id %s is unique" % [kind, id])
			seen[id] = true
			assert_ne(Catalog.display_name(kind, id), id, "%s %s has a name" % [kind, id])
	assert_eq(Catalog.crash("nope"), null)
	assert_eq(Catalog.plate("nope"), null)
	assert_eq(Catalog.display_name(Catalog.CRASH, "little_ghost"), "Little Ghost")
	assert_eq(Catalog.display_name(Catalog.PLATE, "royal"), "Royal")


func test_prices_and_free_defaults() -> void:
	assert_eq(Shop.starters(Catalog.CRASH), [CrashStyle.DEFAULT_ID], "one free crash effect")
	assert_eq(Shop.starters(Catalog.PLATE), [PlateStyle.DEFAULT_ID], "one free plate")
	for kind: String in [Catalog.CRASH, Catalog.PLATE]:
		for id in Catalog.ids(kind):
			var cost := Shop.price(kind, id)
			assert_true(cost >= 0 and cost <= 1200, "%s %s costs %d" % [kind, id, cost])
			assert_eq(cost % 50, 0, "%s %s is a round price" % [kind, id])
	assert_eq(Shop.price(Catalog.CRASH, "little_ghost"), 600)
	assert_eq(Shop.price(Catalog.PLATE, "royal"), 800)
	for id in FLAP_TRAILS:
		assert_true(Shop.price(Catalog.TRAIL, id) >= 200, "%s has a price" % id)


func test_buying_and_using() -> void:
	var p := Profile.new()
	assert_eq(Shop.buy(p, Catalog.CRASH, "firework"), Shop.Result.NOT_ENOUGH_COINS)
	p.coins = 2000
	assert_eq(Shop.buy(p, Catalog.CRASH, "firework"), Shop.Result.OK)
	assert_eq(Shop.buy(p, Catalog.PLATE, "deep_sea"), Shop.Result.OK)
	assert_eq(p.coins, 2000 - 500 - 400)
	assert_true(p.equip(Catalog.CRASH, "firework"))
	assert_true(p.equip(Catalog.PLATE, "deep_sea"))
	assert_false(p.equip(Catalog.PLATE, "royal"), "not owned")
	assert_eq(CrashStyle.equipped(p).id, "firework")
	assert_eq(PlateStyle.equipped(p).id, "deep_sea")


func test_new_profile_starts_with_the_defaults() -> void:
	var p := Profile.new()
	assert_true(p.owns(Catalog.CRASH, CrashStyle.DEFAULT_ID))
	assert_eq(p.equipped_id(Catalog.CRASH), CrashStyle.DEFAULT_ID)
	assert_true(p.owns(Catalog.PLATE, PlateStyle.DEFAULT_ID))
	assert_eq(p.equipped_id(Catalog.PLATE), PlateStyle.DEFAULT_ID)
	assert_eq(CrashStyle.equipped(null).id, CrashStyle.DEFAULT_ID)
	assert_eq(PlateStyle.equipped(null).id, PlateStyle.DEFAULT_ID)


func test_save_and_load_round_trip() -> void:
	var p := Profile.new()
	p.grant(Catalog.CRASH, "comic_pow")
	p.equip(Catalog.CRASH, "comic_pow")
	p.grant(Catalog.PLATE, "star_station")
	p.equip(Catalog.PLATE, "star_station")
	assert_true(p.save(TEST_PATH))
	var back := Profile.load_or_new(TEST_PATH)
	assert_true(back.owns(Catalog.CRASH, "comic_pow"))
	assert_eq(back.equipped_id(Catalog.CRASH), "comic_pow")
	assert_eq(back.equipped_id(Catalog.PLATE), "star_station")
	DirAccess.remove_absolute(TEST_PATH)


## A save from before these kinds, or one naming an item that is gone, loads
## with the defaults in use.
func test_old_saves_get_the_defaults() -> void:
	var old := Profile.from_dict(
		{"coins": 7, "owned": {"flyer": ["dash"]}, "equipped": {"flyer": "dash"}}
	)
	assert_eq(old.coins, 7)
	assert_eq(old.equipped_id(Catalog.FLYER), "dash")
	assert_eq(old.equipped_id(Catalog.CRASH), CrashStyle.DEFAULT_ID)
	assert_eq(old.equipped_id(Catalog.PLATE), PlateStyle.DEFAULT_ID)
	assert_true(old.owns(Catalog.PLATE, PlateStyle.DEFAULT_ID))
	var gone := (
		Profile
		. from_dict(
			{
				"owned": {"crash": ["removed_one"], "plate": ["removed_two"]},
				"equipped": {"crash": "removed_one", "plate": "removed_two"},
			}
		)
	)
	assert_eq(gone.equipped_id(Catalog.CRASH), CrashStyle.DEFAULT_ID)
	assert_eq(gone.equipped_id(Catalog.PLATE), PlateStyle.DEFAULT_ID)


func test_crash_styles_are_complete() -> void:
	var spikes := _spikes()
	for c in Catalog.crashes():
		assert_false(c.blurb.is_empty(), "%s has a blurb" % c.id)
		assert_true(c.colors.size() > 0, "%s has colours" % c.id)
		assert_true(c.count > 0, "%s has pieces" % c.id)
		assert_true(c.thumb_time() > 0.0, "%s has a shop moment" % c.id)
		assert_eq(c.loops(), c.duration() == 0.0, "%s either ends or stays" % c.id)
		if not c.loops():
			assert_true(c.thumb_time() < c.duration(), "%s shop moment is inside its life" % c.id)
		if c.kind == CrashStyle.BURST:
			assert_true(CrashPainter.MOTION.has(c.piece), "%s throws a known piece" % c.id)
		for col in c.colors:
			var hex := col.to_html(false)
			assert_false(spikes.has(hex), "%s uses %s, the %s spike" % [c.id, hex, spikes.get(hex)])
	for col: Color in [CrashPainter.INK, CrashPainter.FEATHER_SHADE]:
		assert_false(spikes.has(col.to_html(false)), "a fixed crash colour is a spike colour")
	assert_true(Catalog.crash("shatter").hides_flyer, "Shatter replaces the flyer")
	assert_false(Catalog.crash("comic_pow").in_front, "Comic Pow pops behind the flyer")


func test_crash_painter_is_repeatable() -> void:
	assert_eq(CrashPainter.rnd(3, 2), CrashPainter.rnd(3, 2), "the same piece, the same path")
	for i in 20:
		var v := CrashPainter.rnd(i, 1)
		assert_true(v >= 0.0 and v < 1.0, "rnd stays in 0..1 (%f)" % v)
	assert_eq(CrashPainter.ease_out(1.0), 1.0)
	assert_true(is_equal_approx(CrashPainter.back_out(1.0), 1.0), "a pop ends at full size")
	assert_true(CrashPainter.back_out(0.6) > 1.0, "a pop overshoots on the way")
	assert_eq(CrashPainter.flyer_palette(null).size(), 0, "no art, no palette")


## Every style drawn at many moments of its life, both ways round, big and
## small: any error logged while drawing fails the test.
func test_every_crash_effect_draws_through_its_life() -> void:
	var view := CrashView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	var palette := CrashPainter.flyer_palette(Catalog.flyer("dash").idle)
	for c in Catalog.crashes():
		for away: float in [-1.0, 1.0]:
			view.play(c, Vector2(180, 320), away, palette)
			assert_true(view.is_playing(), "%s plays" % c.id)
			assert_eq(view.z_index, 1 if c.in_front else 0, "%s layer" % c.id)
			for t: float in [0.0, 0.05, 0.2, 0.5, 0.9, 1.25]:
				view._time = t
				view.queue_redraw()
				await _frames()
		if not c.loops():
			view._time = c.duration()
			await _frames(2)
			assert_false(view.is_playing(), "%s ends" % c.id)
	view.clear()
	assert_false(view.is_playing(), "cleared for the next run")
	view.free()


## A crash in a real run starts the equipped effect; a new run clears it.
func test_a_crash_plays_the_equipped_effect() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._profile.grant(Catalog.FLYER, "dash")
	main._profile.equip(Catalog.FLYER, "dash")
	main._profile.grant(Catalog.CRASH, "shatter")
	main._profile.equip(Catalog.CRASH, "shatter")
	main._load_equipped()
	main.start_run()
	main._run.request_tap()
	await _frames(2)
	assert_false(main._crash.is_playing(), "nothing plays during the run")
	# What _on_died does first, without sending the run anywhere.
	main._play_crash()
	assert_true(main._crash.is_playing(), "the effect starts on the crash")
	assert_eq(main._crash.style.id, "shatter")
	await _frames(3)
	assert_true(main._bird.modulate.a < 1.0, "Shatter fades the flyer out")
	main._new_run()
	assert_false(main._crash.is_playing(), "a new run clears it")
	assert_eq(main._bird.modulate.a, 1.0, "and the flyer is back")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_plates_are_complete() -> void:
	for p in Catalog.plates():
		assert_false(p.blurb.is_empty(), "%s has a blurb" % p.id)
		assert_eq(p.is_plain(), p.id == PlateStyle.DEFAULT_ID, "only Paper is plain")
		# Text reads on the plate's base colour (4.5:1).
		var ratio := Contrast.ratio(p.text_color(), p.base)
		assert_true(ratio >= 4.5, "%s text contrast is %.1f" % [p.id, ratio])
		# Your own row is gold: no plate is gold all over.
		assert_ne(p.base.to_html(false), UiTokens.ACTION.to_html(false), "%s is not gold" % p.id)


func test_plate_pill_and_area() -> void:
	var pts := PlatePainter.pill(Rect2(0, 0, 200, 48))
	var seen := {}
	for v in pts:
		assert_true(v.x >= -0.01 and v.x <= 200.01 and v.y >= -0.01 and v.y <= 48.01, "inside")
		assert_false(seen.has(v), "no point twice")
		seen[v] = true
	var square := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	assert_eq(absf(PlatePainter.area(square)), 4.0)


## Every plate behind a row at several widths, as your own row too, and in the
## shop pictures.
func test_every_plate_draws() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(360, 640)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var list := VBoxContainer.new()
	list.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(list)
	for p in Catalog.plates():
		for mine: bool in [false, true]:
			var e := LeaderboardBoard.Entry.new(4, "TapTapLeo_1234", "dash", 87)
			e.is_me = mine
			e.plate_id = p.id
			var row := LeaderboardRow.new(e)
			list.add_child(row)
			assert_eq(row.plate == null, p.is_plain(), "%s row plate" % p.id)
		var thumb := ItemThumb.new()
		thumb.world = ThemeCatalog.default_theme()
		thumb.plate = p
		thumb.flyer = Catalog.flyer("dash").idle
		thumb.custom_minimum_size = Vector2(264, 80)
		list.add_child(thumb)
	await _frames(2)
	for width: float in [120.0, 332.0, 600.0]:
		holder.size.x = width
		await _frames(2)
	holder.free()


func test_rows_with_a_dark_plate_have_white_text() -> void:
	var e := LeaderboardBoard.Entry.new(2, "Noor", "pip", 120)
	e.plate_id = "star_station"
	var row := LeaderboardRow.new(e)
	var labels := row.find_children("*", "Label", true, false)
	assert_true(labels.size() >= 3, "rank, name and score")
	for l in labels:
		assert_eq((l as Label).get_theme_color("font_color"), UiTokens.ON_SCRIM, "white text")
	row.free()
	var unknown := LeaderboardBoard.Entry.new(2, "Noor", "pip", 120)
	unknown.plate_id = "not_a_plate"
	var plain := LeaderboardRow.new(unknown)
	assert_eq(plain.plate, null, "an unknown plate is the plain row")
	plain.free()


func test_boards_carry_plates() -> void:
	var board := (
		SupabaseLeaderboard
		. parse_board(
			LeaderboardService.DAILY,
			{
				"entries":
				[
					{"rank": 1, "name": "Noor", "flyer": "pip", "score": 90, "plate": "royal"},
					{"rank": 2, "name": "Jun", "flyer": "dash", "score": 80},
				]
			}
		)
	)
	assert_eq(board.entries[0].plate_id, "royal")
	assert_eq(board.entries[1].plate_id, "", "an older database sends none")
	var p := Profile.new()
	p.best_score = 400
	p.grant(Catalog.PLATE, "lava_forge")
	p.equip(Catalog.PLATE, "lava_forge")
	var sample := SampleLeaderboard.new(p).build_board(LeaderboardService.ALL_TIME)
	assert_eq(sample.me.plate_id, "lava_forge", "your own row shows your plate")
	var look := LeaderboardService.loadout_of(p)
	assert_eq(look[Catalog.PLATE], "lava_forge", "the plate goes along with a run")
	assert_eq(look[Catalog.CRASH], CrashStyle.DEFAULT_ID, "and so does the crash effect")


func test_flap_trails_stamp_once_per_flap() -> void:
	var spikes := _spikes()
	for id in FLAP_TRAILS:
		var t := Catalog.trail(id)
		assert_true(t != null, "%s is in the catalog" % id)
		if t == null:
			continue
		assert_eq(t.kind, TrailStyle.Kind.STAMPS, "%s is a stamp trail" % id)
		assert_true(t.stamp_on_flap, "%s leaves one stamp per flap" % id)
		for col in t.colors:
			assert_false(spikes.has(col.to_html(false)), "%s uses a spike colour" % id)
	for col: Color in [
		TrailPainter.FEATHER_SHADE, TrailPainter.BLOSSOM_HEART, TrailPainter.FLAME_CORE
	]:
		assert_false(spikes.has(col.to_html(false)), "a fixed trail colour is a spike colour")
	var shapes := {}
	for t in TrailStyle.flap_trails():
		assert_false(shapes.has(t.shape), "%s has its own shape" % t.id)
		shapes[t.shape] = true
	assert_eq(TrailPainter.heart_points(10.0).size(), 12, "a heart's outline")


## The Customize tabs for the new kinds open, preview and buy like the others.
func test_customize_tabs_for_the_new_kinds() -> void:
	var p := Profile.new()
	p.grant(Catalog.FLYER, "buzz")
	p.equip(Catalog.FLYER, "buzz")
	p.coins = Shop.price(Catalog.CRASH, "dizzy_stars")
	var shop := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.CRASH)
	(Engine.get_main_loop() as SceneTree).root.add_child(shop)
	assert_eq(shop.title_text(), "Crashes")
	assert_eq(CollectionScreen.title_for(Catalog.PLATE), "Plates")
	assert_eq(shop.item_ids(), Catalog.ids(Catalog.CRASH), "every crash effect is listed")
	assert_eq(shop.caption_text(), "Feather Puff, in use")
	shop._tap("dizzy_stars")
	assert_eq(shop.action_label(), ["Unlock for 300", true])
	shop._on_action()
	assert_eq(p.equipped_id(Catalog.CRASH), "dizzy_stars", "bought and put to use")
	assert_eq(p.coins, 0)
	shop._show_kind(Catalog.PLATE)
	assert_eq(shop.caption_text(), "Paper, in use")
	shop._tap("royal")
	assert_eq(shop.action_label(), ["Need 800 more coins", false])
	await _frames(2)
	shop.free()
