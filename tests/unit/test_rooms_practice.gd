extends TestCase
## The Rooms screen and practice (Rooms button, list, detail, practice runs):
## which rooms are open, cleared counts from real runs only, and practice runs
## that repeat one room without counting.

const TEST_PATH := "user://test_rooms_profile.json"


## Developer mode opens every room; most tests here check the real unlock rule.
func _real_mode() -> void:
	DevMode.override = 0


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	_use_flyer(main, "buzz")
	return main


## Scores points until the room changes (10 points), without flying.
## Scores a room's points, then flies through the exit that opens (rooms change
## through exit portals since gameplay version 5).
func _finish_room(sim: GameSim) -> void:
	for i in SimConfig.POINTS_PER_ROOM - 1:
		sim._score()
	var r := SimConfig.BIRD_RADIUS
	# Bounce off the left wall: the 10th point opens an exit on the right wall.
	sim.state.y = 300 * SimConfig.SUB
	sim.state.vx = -SimConfig.SPEED_X
	sim.state.x = sim.room.wall_left() + r - 1
	sim._check_walls()
	# Fly into it.
	sim.state.y = sim.state.exit_a_y
	sim.state.vx = SimConfig.SPEED_X
	sim.state.x = sim.room.wall_right() - r + 1
	sim._check_walls()


func test_every_room_has_display_info() -> void:
	for def in RoomCatalog.all():
		assert_true(RoomInfo.ROOMS.has(def.id), "%s has a name and pitch" % def.id)
		assert_false(RoomInfo.pitch(def.id).is_empty(), "%s pitch" % def.id)
		var d := RoomInfo.difficulty(def.id)
		assert_true(d >= 1 and d <= 5, "%s difficulty 1 to 5" % def.id)
		assert_true(RoomInfo.group(def) in RoomInfo.GROUPS, "%s has a card group" % def.id)


func test_practice_repeats_one_room_from_its_start_score() -> void:
	var i := RoomCatalog.index_of("piston")
	var sim := GameSim.new(7, Seasons.NONE, i)
	assert_true(sim.is_practice(), "practice run")
	assert_eq(sim.state.room_kind, i, "starts in the practice room")
	assert_eq(sim.state.score, RoomCatalog.find("piston").from_score, "starts at its from score")
	_finish_room(sim)
	assert_eq(sim.state.room_kind, i, "the same room comes back")
	assert_eq(sim.shown_score(), SimConfig.POINTS_PER_ROOM, "points count from 0")
	var real := GameSim.new(7)
	assert_false(real.is_practice(), "a real run is not practice")
	assert_eq(real.state.room_kind, RoomCatalog.first_index(), "real runs start in Open Sky")


func test_profile_counts_met_and_cleared_rooms_and_saves_them() -> void:
	var p := Profile.new()
	assert_false(p.has_met_room("open"))
	p.record_room_met("open")
	p.record_room_cleared("open")
	p.record_room_cleared("open")
	p.record_room_cleared("tide")
	assert_true(p.has_met_room("tide"), "clearing a room also meets it")
	assert_eq(p.clears("open"), 2)
	assert_eq(p.total_clears(), 3)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.clears("open"), 2, "clears survive a save")
	assert_true(back.has_met_room("tide"), "met rooms survive a save")


func test_room_status_says_cleared_or_why_it_is_locked() -> void:
	DevMode.override = 0
	var p := Profile.new()
	p.best_score = 87
	p.record_room_cleared("open")
	p.record_room_met("tide")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("open")), "Cleared 1 of 1")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("tide")), "Not cleared yet")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("piston")), "Not met yet", "reachable, not met")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("pinwheel")), "Reach 90 points")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("pumpkin")), "October only")
	assert_true(RoomInfo.is_open(p, RoomCatalog.find("tide")), "met rooms are open")
	assert_false(RoomInfo.is_open(p, RoomCatalog.find("piston")), "unmet rooms are locked")


func test_rooms_screen_lists_every_room_and_locks_unmet_ones() -> void:
	DevMode.override = 0
	var p := Profile.new()
	p.record_room_cleared("open")
	p.record_room_cleared("open")
	var screen := RoomsScreen.new(p)
	screen.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_eq(screen.cleared_text(), "2", "the header shows the total clears")
	assert_eq(screen.group_cards()[0].count_text(), "1 of %d" % RoomInfo.rooms_in("starter").size())
	screen.free()
	var cards := _all_room_cards(p)
	assert_eq(cards.size(), RoomCatalog.all().size(), "a card per room kind")
	for card in cards:
		assert_eq(card.disabled, card.room_id != "open", "%s locked unless met" % card.room_id)
		card.free()


## Every room card, from each group's screen (taken out of it).
func _all_room_cards(p: Profile) -> Array[RoomCard]:
	var out: Array[RoomCard] = []
	for g in RoomInfo.GROUPS:
		var screen := RoomsScreen.new(p, g)
		(Engine.get_main_loop() as SceneTree).root.add_child(screen)
		for card in screen.cards():
			card.get_parent().remove_child(card)
			out.append(card)
		screen.free()
	return out


func test_room_detail_shows_clears_and_only_practices_open_rooms() -> void:
	DevMode.override = 0
	var p := Profile.new()
	p.record_room_cleared("piston")
	var open := RoomDetailScreen.new(p, "piston")
	open.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(open)
	assert_eq(open.stat_text("cleared"), "1")
	assert_false(open.practice_button().disabled, "an open room can be practised")
	open.free()
	var locked := RoomDetailScreen.new(p, "flip")
	(Engine.get_main_loop() as SceneTree).root.add_child(locked)
	assert_eq(locked.stat_text("cleared"), "", "a locked room has no stats")
	assert_true(locked.practice_button().disabled, "a locked room can't be practised")
	assert_eq(locked.locked_reason(), RoomInfo.status(p, RoomCatalog.find("flip")), "says why")
	locked.free()


func test_real_runs_count_clears_and_practice_never_does() -> void:
	DevMode.override = 0
	var main := _make_main()
	main.start_run()
	main._on_run_started()
	assert_true(main._profile.has_met_room("open"), "the first room is met")
	_finish_room(main._run.sim)
	main._on_room_changed(1)
	assert_eq(main._profile.clears("open"), 1, "surviving a room clears it")
	var next: String = main._room_id
	assert_true(main._profile.has_met_room(next), "the next room is met")
	# Practice the room just met: nothing it does counts.
	main.start_practice(next)
	assert_eq(main.mode, main.Mode.PRACTICE)
	assert_true(main._run.sim.is_practice(), "the sim repeats the room")
	assert_true(main._hud.is_practicing(), "the HUD says practice")
	var coins_before: int = main._profile.coins
	var best_before: int = main._profile.best_score
	_finish_room(main._run.sim)
	main._on_room_changed(2)
	assert_eq(main._profile.clears(next), 0, "practice clears don't count")
	main._on_died(Replay.from_sim(main._run.sim, PackedInt32Array()))
	assert_eq(main._profile.coins, coins_before, "no coins from practice")
	assert_eq(main._profile.best_score, best_before, "no best score from practice")
	assert_true(main._hud.practice_hud().is_over_showing(), "the practice crash screen shows")
	main.show_rooms()
	var back := main._menus.current() as RoomsScreen
	assert_true(back != null, "Back to rooms")
	if back != null:
		var def := RoomCatalog.find(next)
		assert_eq(back.group(), RoomInfo.group(def), "on the practised room's group")
	assert_false(main._hud.is_practicing(), "the practice HUD hides in menus")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_locked_rooms_cannot_be_practised() -> void:
	DevMode.override = 0
	var main := _make_main()
	main.start_practice("flip")
	assert_eq(main.mode, main.Mode.MENU, "flip was never met, so no practice")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_home_has_a_rooms_button() -> void:
	var main := _make_main()
	var home := main._menus.current() as HomeScreen
	assert_true(home != null, "home is showing")
	if home != null:
		home.rooms_pressed.emit()
		var rooms := main._menus.current() as RoomsScreen
		assert_true(rooms != null, "Rooms opens the Rooms screen")
		if rooms != null:
			assert_eq(rooms.group(), "", "on the room groups")
			rooms.group_opened.emit("bonus")
			var bonus := main._menus.current() as RoomsScreen
			assert_eq(bonus.group(), "bonus", "a group opens its rooms")
			bonus.room_opened.emit(RoomInfo.rooms_in("bonus")[0].id)
			(main._menus.current() as RoomDetailScreen).closed.emit()
			assert_eq((main._menus.current() as RoomsScreen).group(), "bonus", "back to the group")
			(main._menus.current() as RoomsScreen).closed.emit()
			assert_eq((main._menus.current() as RoomsScreen).group(), "", "back to the groups")
			(main._menus.current() as RoomsScreen).closed.emit()
			assert_true(main._menus.current() is HomeScreen, "and Home")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_developer_mode_opens_every_room_and_shows_dev() -> void:
	DevMode.override = 1
	var p := Profile.new()
	for def in RoomCatalog.all():
		assert_true(RoomInfo.is_open(p, def), "%s open in developer mode" % def.id)
	var screen := RoomsScreen.new(p)
	screen.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_true(screen.has_dev_tag(), "the Rooms screen says DEV")
	screen.free()
	for card in _all_room_cards(p):
		assert_false(card.disabled, "%s can be opened" % card.room_id)
		card.free()
	DevMode.override = 0
	var off := RoomsScreen.new(p)
	(Engine.get_main_loop() as SceneTree).root.add_child(off)
	assert_false(off.has_dev_tag(), "no DEV tag in a release build")
	off.free()
	DevMode.override = -1


func test_seasonal_practice_plays_in_its_season() -> void:
	DevMode.override = 1
	var main := _make_main()
	main.season = Seasons.NONE
	main.start_practice("pumpkin")
	assert_eq(main.mode, main.Mode.PRACTICE, "dev mode practises seasonal rooms")
	assert_eq(main._run.sim.season, Seasons.HALLOWEEN, "a Halloween room runs in Halloween")
	assert_eq(main._run.sim.state.room_kind, RoomCatalog.index_of("pumpkin"))
	main.free()
	SafeFile.remove(TEST_PATH)
	DevMode.override = -1


## Practice's "Tap to flap" back arrow goes back to Rooms, not Home.
func test_practice_ready_back_arrow_goes_to_rooms() -> void:
	DevMode.override = 1
	var main := _make_main()
	main.start_practice("piston")
	var hud: Hud = main._hud
	assert_true(hud._back_button.visible, "the back arrow shows before the first flap")
	assert_eq(hud._back_button.tooltip_text, "Rooms")
	hud._back_button.pressed.emit()
	assert_eq(main.mode, main.Mode.MENU)
	assert_true(main._menus.current() is RoomsScreen, "back goes to Rooms")
	assert_false(hud._back_button.visible, "no back arrow over the menus")
	main.free()
	SafeFile.remove(TEST_PATH)
	DevMode.override = -1


## Practice must never change the save: same profile and the same file after a
## whole practice run, its room changes and its crash.
func test_practice_never_changes_the_save() -> void:
	DevMode.override = 1
	var main := _make_main()
	main._profile.coins = 120
	main._profile.best_score = 33
	main._profile.record_room_cleared("open")
	main._profile.save(TEST_PATH)
	var before := FileAccess.get_file_as_string(TEST_PATH)
	var data_before := JSON.stringify(main._profile.to_dict())
	for id in ["piston", "garden", "pumpkin"]:
		main.start_practice(id)
		main._on_run_started()
		for room in 3:
			_finish_room(main._run.sim)
			main._on_room_changed(room + 1)
		main._on_died(Replay.from_sim(main._run.sim, PackedInt32Array()))
		main._restart_practice()
	assert_eq(JSON.stringify(main._profile.to_dict()), data_before, "profile unchanged")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), before, "save file unchanged")
	main.free()
	SafeFile.remove(TEST_PATH)
	DevMode.override = -1


func test_old_version_1_saves_still_load() -> void:
	var old := {"version": 1, "coins": 50, "best_score": 12, "onboarded": true}
	var p := Profile.from_dict(old)
	assert_eq(p.coins, 50)
	assert_eq(p.total_clears(), 0, "no clears in an old save")
	assert_eq(int(p.to_dict()["version"]), Profile.VERSION, "saved again as the current version")


## Puts a flyer (and optionally a world) in use, as Customize would; a first
## start already gave the default world.
static func _use_flyer(main: Node, id: String, world: String = "") -> void:
	main._profile.grant(ItemKind.FLYER, id)
	main._profile.equip(ItemKind.FLYER, id)
	if not world.is_empty():
		main._profile.grant(ItemKind.WORLD, world)
		main._profile.equip(ItemKind.WORLD, world)
	main._look.use_equipped()
