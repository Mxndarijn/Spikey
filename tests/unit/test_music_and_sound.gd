extends TestCase
## Music as a Customize kind (catalog, prices, the pick in the save), the Music
## tab with its previews, and the settings sheet behind Home's Settings.

const TEST_PATH := "user://test_music_profile.json"
const MAIN_SCENE := "res://game/main.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _holder() -> Control:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(holder)
	return holder


func test_music_catalog_and_prices() -> void:
	var ids := Catalog.ids(Catalog.MUSIC)
	assert_eq(ids.slice(0, 2), [MusicTrack.MATCH_WORLD, MusicTrack.SHUFFLE], "picks come first")
	assert_eq(ids.size(), 2 + MusicTrack.all().size(), "then every track")
	assert_eq(Catalog.tracks().size(), 5)
	assert_eq(Catalog.track("lava_rush").bpm, 140)
	assert_true(Catalog.track(MusicTrack.MATCH_WORLD) == null, "picks are not tracks")
	assert_eq(Catalog.display_name(Catalog.MUSIC, MusicTrack.MATCH_WORLD), "Match my world")
	assert_eq(Catalog.display_name(Catalog.MUSIC, MusicTrack.SHUFFLE), "Shuffle owned")
	assert_eq(Catalog.display_name(Catalog.MUSIC, "star_arcade"), "Star Arcade")
	var prices := {
		MusicTrack.MATCH_WORLD: 0,
		MusicTrack.SHUFFLE: 0,
		"candy_hop": 0,
		"bubble_drift": 300,
		"jungle_bounce": 300,
		"lava_rush": 400,
		"star_arcade": 400,
	}
	for id: String in prices:
		assert_eq(Shop.price(Catalog.MUSIC, id), prices[id], "%s price" % id)
	assert_eq(
		Shop.starters(Catalog.MUSIC), [MusicTrack.MATCH_WORLD, MusicTrack.SHUFFLE, "candy_hop"]
	)


func test_profile_saves_the_music_pick_and_settings() -> void:
	var p := Profile.new()
	for id in [MusicTrack.MATCH_WORLD, MusicTrack.SHUFFLE, "candy_hop"]:
		assert_true(p.owns(Catalog.MUSIC, id), "%s is owned from the start" % id)
	assert_false(p.owns(Catalog.MUSIC, "lava_rush"))
	assert_eq(p.equipped_id(Catalog.MUSIC), MusicTrack.MATCH_WORLD, "Match my world plays")
	p.coins = 300
	assert_eq(Shop.buy(p, Catalog.MUSIC, "bubble_drift"), Shop.Result.OK)
	assert_true(p.equip(Catalog.MUSIC, "bubble_drift"))
	p.music_volume = 35
	p.sfx_volume = 60
	p.music_on = false
	assert_true(p.save(TEST_PATH))
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.equipped_id(Catalog.MUSIC), "bubble_drift")
	assert_true(back.owns(Catalog.MUSIC, "bubble_drift"))
	assert_eq(
		[back.music_volume, back.sfx_volume, back.music_on, back.sfx_on], [35, 60, false, true]
	)
	DirAccess.remove_absolute(TEST_PATH)


func test_old_saves_get_the_music_defaults() -> void:
	var old := Profile.from_dict({"coins": 5, "owned": {"trail": ["world_ribbon"]}})
	assert_eq(old.equipped_id(Catalog.MUSIC), MusicTrack.MATCH_WORLD)
	assert_true(old.owns(Catalog.MUSIC, "candy_hop"))
	assert_eq([old.music_volume, old.sfx_volume, old.music_on, old.sfx_on], [80, 100, true, true])
	var odd := Profile.from_dict({"music_volume": 400, "sfx_volume": -3})
	assert_eq([odd.music_volume, odd.sfx_volume], [100, 0], "volumes stay in 0..100")


func test_music_tab_lists_previews_and_buys() -> void:
	var holder := _holder()
	var p := Profile.new()
	p.coins = 350
	var c := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.MUSIC)
	var bought: Array[String] = []
	c.equipped.connect(func(_k: String, id: String) -> void: bought.append(id))
	holder.add_child(c)
	assert_eq(c.title_text(), "Music", "the Music list")
	assert_eq(c.item_ids().slice(0, 3), [MusicTrack.MATCH_WORLD, MusicTrack.SHUFFLE, "candy_hop"])
	assert_eq(c.selected_id(), MusicTrack.MATCH_WORLD, "the pick in use is selected")
	assert_eq(c._owned_grid.columns, 1, "music cards are rows")
	var cards := {}
	for card in c._cards:
		assert_eq(card.layout, ItemCard.Layout.TRACK, "%s is a playlist row" % card.item_id)
		cards[card.item_id] = card
	assert_eq((cards["candy_hop"] as ItemCard)._blurb.text, "120 BPM · Bright and bouncy")
	assert_eq((cards["bubble_drift"] as ItemCard).status_text(), "300")
	c.toggle_preview("bubble_drift")
	assert_eq(c.playing_id(), "bubble_drift", "the play button previews")
	assert_true((cards["bubble_drift"] as ItemCard).is_playing(), "and turns into stop")
	c.toggle_preview("lava_rush")
	assert_false((cards["bubble_drift"] as ItemCard).is_playing(), "one preview at a time")
	c.toggle_preview("lava_rush")
	assert_eq(c.playing_id(), "", "stop ends the preview")
	assert_eq(c.preview_track(MusicTrack.MATCH_WORLD).id, MusicTrack.for_world(c._backdrop().id).id)
	c._tap("lava_rush")
	assert_eq(c._popup_thumb.music, "lava_rush", "the popup shows the record")
	assert_true(c._badge_text.text.begins_with("Matches "), "and the worlds it matches")
	assert_eq(c.action_label(), ["Need 50 more coins", false])
	c.toggle_preview("bubble_drift")
	c._tap("bubble_drift")
	c._on_action()
	assert_eq(p.equipped_id(Catalog.MUSIC), "bubble_drift", "bought and put to use")
	assert_eq(bought, ["bubble_drift"], "main hears about it")
	assert_eq(c.playing_id(), "", "the preview hands over to the new pick")
	c._show_kind(Catalog.FLYER)
	assert_eq(c._owned_grid.columns, CollectionScreen.SHOP_COLUMNS, "other tabs stay grids")
	holder.free()


func test_settings_sheet_edits_the_profile() -> void:
	var holder := _holder()
	var p := Profile.new()
	var home := HomeScreen.new(p)
	holder.add_child(home)
	var changes := [0]
	home.settings_changed.connect(func() -> void: changes[0] += 1)
	var sheet := home.open_settings()
	assert_true(sheet != null and sheet.get_parent() == home, "Settings opens the sheet")
	assert_eq(sheet.value_text("music"), "80", "shows the saved volume")
	sheet.set_volume("music", 35)
	assert_eq(p.music_volume, 35)
	assert_eq(sheet.value_text("music"), "35")
	sheet.set_on("sfx", false)
	assert_false(p.sfx_on, "the round button turns sounds off")
	assert_true(sheet.slider("sfx").faded, "and fades its slider")
	assert_eq(changes[0], 2, "each change is reported")
	for key: String in SettingsSheet.SWITCHES:
		assert_true(sheet.switch(key) != null, "a %s switch" % key)
	assert_true(sheet.switch("haptics").button_pressed, "haptics start on")
	sheet.set_switch("reduced_flashing", true)
	sheet.set_switch("large_buttons", true)
	sheet.set_switch("color_blind_spikes", true)
	assert_true(p.reduced_flashing and p.large_buttons and p.color_blind_spikes, "saved in profile")
	assert_eq(changes[0], 5)
	assert_false(sheet.is_showing_credits())
	sheet.show_credits(true)
	assert_true(sheet.is_showing_credits(), "Credits and licenses")
	sheet.close_dialog()
	assert_true(home.settings() == null, "the close button closes it")
	holder.free()


## The knob stays inside the bar at 0 and 100 (it used to run into the value).
func test_volume_knob_stays_inside_the_bar() -> void:
	var holder := _holder()
	var slider := VolumeSlider.new()
	holder.add_child(slider)
	slider.size = Vector2(200, VolumeSlider.HEIGHT)
	assert_eq(slider.value_at(0.0), 0.0)
	assert_eq(slider.value_at(200.0), 100.0)
	slider.value = 100
	assert_eq(slider.knob_x() + VolumeSlider.KNOB / 2.0, 200.0, "the knob ends at the bar's end")
	slider.value = 0
	assert_eq(slider.knob_x() - VolumeSlider.KNOB / 2.0, 0.0, "and starts at its start")
	holder.free()


func test_play_settings_are_saved_and_applied() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load(MAIN_SCENE).instantiate()
	main.profile_path = TEST_PATH
	_tree().root.add_child(main)
	var home := main._menus.current() as HomeScreen
	if home == null:
		fail("starts on home")
		main.free()
		return
	var sheet := home.open_settings()
	sheet.set_switch("reduced_flashing", true)
	assert_false(main._room.flash_enabled, "reduced flashing turns the room flash off")
	sheet.set_switch("large_buttons", true)
	assert_eq(main._hud._pause_button.custom_minimum_size, Vector2(56, 56), "large pause")
	sheet.set_switch("haptics", false)
	var saved := Profile.load_or_new(TEST_PATH)
	assert_true(saved.reduced_flashing and saved.large_buttons, "saved at once")
	assert_false(saved.haptics)
	sheet.set_switch("reduced_flashing", false)
	assert_true(main._room.flash_enabled, "and back on")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)
	UiKit.large_buttons = false


func test_old_saves_get_the_play_setting_defaults() -> void:
	var old := Profile.from_dict({"coins": 5})
	assert_eq(
		[old.haptics, old.reduced_flashing, old.color_blind_spikes, old.large_buttons],
		[true, false, false, false]
	)
	var p := Profile.new()
	p.color_blind_spikes = true
	assert_true(Profile.from_dict(p.to_dict()).color_blind_spikes, "round trip")


func test_main_saves_sound_settings_from_home() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load(MAIN_SCENE).instantiate()
	main.profile_path = TEST_PATH
	_tree().root.add_child(main)
	_use_flyer(main, "buzz")
	var home := main._menus.current() as HomeScreen
	assert_true(home != null, "home")
	if home != null:
		home.open_settings().set_volume("music", 20)
		assert_eq(Profile.load_or_new(TEST_PATH).music_volume, 20, "saved at once")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Puts a flyer in use, as Customize would (first start already gave Sunset Glow).
static func _use_flyer(main: Node, id: String) -> void:
	main._profile.grant(Catalog.FLYER, id)
	main._profile.equip(Catalog.FLYER, id)
	main._load_equipped()
