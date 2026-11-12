extends TestCase
## Per-room stats from real runs (reached, cleared, deaths): counting from the
## run's events, revives, practice, the save and its migration, the merge with
## the server's copy, and where the Rooms screens show them.

const TEST_PATH := "user://test_room_stats_profile.json"


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


static func _fall(main: Node) -> void:
	while not main._run.sim.is_over():
		main._run.advance()


static func _tap(main: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)


## Scores a room's points and flies through the exit, as in test_rooms_practice.
static func _finish_room(sim: GameSim) -> void:
	for i in SimConfig.POINTS_PER_ROOM - 1:
		sim._score()
	var r := SimConfig.BIRD_RADIUS
	sim.state.y = 300 * SimConfig.SUB
	sim.state.vx = -SimConfig.SPEED_X
	sim.state.x = sim.room.wall_left() + r - 1
	sim._check_walls()
	sim.state.y = sim.state.exit_a_y
	sim.state.vx = SimConfig.SPEED_X
	sim.state.x = sim.room.wall_right() - r + 1
	sim._check_walls()


static func _roundtrip(p: Profile) -> Profile:
	return Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))


func test_counts_follow_a_scripted_run() -> void:
	var p := Profile.new()
	# Run 1: reach Open Sky, die there.
	p.record_room_reached("open")
	p.record_room_death("open")
	# Run 2: reach it, clear it, reach Tide, crash, revive, clear Tide.
	p.record_room_reached("open")
	p.record_room_cleared("open")
	p.record_room_reached("tide")
	p.record_room_death("tide")
	p.record_room_cleared("tide")
	assert_eq([p.reached("open"), p.clears("open"), p.deaths("open")], [2, 1, 1])
	assert_eq([p.reached("tide"), p.clears("tide"), p.deaths("tide")], [1, 1, 1])
	assert_true(p.has_met_room("tide"), "reaching a room meets it")
	assert_eq(p.clear_rate("open"), 50)
	assert_eq(p.clear_rate("tide"), 100, "a revived room can still be cleared")
	assert_eq(p.clear_rate("piston"), 0, "never reached")
	p.record_room_reached("")
	p.record_room_death("")
	assert_false(p.room_reached.has(""), "no id, no count")


func test_a_real_run_counts_reach_death_revive_and_clear() -> void:
	DevMode.override = 0
	var main := _make_main()
	var p: Profile = main._profile
	main.start_run()
	main._run.request_tap()
	main._run.advance()
	var first: String = main._room_id
	assert_eq(p.reached(first), 1, "the first tap reaches the first room")
	main._run.sim.state.score = ReviveFlow.MIN_SCORE + 4
	_fall(main)
	assert_eq(p.deaths(first), 1, "the crash is a death")
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible, "a revive is offered")
	offer.revive_button().pressed.emit()
	assert_false(main._run.sim.is_over(), "revived")
	_tap(main)
	assert_eq(p.reached(first), 1, "a revive is not a new reach")
	_finish_room(main._run.sim)
	main._on_room_changed(1)
	assert_eq(p.clears(first), 1, "cleared after the revive")
	var next: String = main._room_id
	assert_ne(next, first)
	assert_eq(p.reached(next), 1, "the next room is reached")
	_fall(main)
	assert_eq(p.deaths(next), 1)
	assert_eq(p.deaths(first), 1, "the first room's death stays one")
	var saved := Profile.load_or_new(TEST_PATH)
	assert_eq(saved.deaths(next), 1, "the run's stats are saved when it ends")
	assert_eq(saved.clears(first), 1)
	_free(main)


func test_practice_never_counts() -> void:
	DevMode.override = 0
	var main := _make_main()
	var id := RoomCatalog.all()[RoomCatalog.first_index()].id
	main._profile.record_room_met(id)
	main.start_practice(id)
	main._run.request_tap()
	main._run.advance()
	_fall(main)
	assert_eq(main._profile.reached(id), 0, "practice reaches don't count")
	assert_eq(main._profile.deaths(id), 0, "practice deaths don't count")
	_free(main)


func test_stats_survive_a_save() -> void:
	var p := Profile.new()
	p.record_room_reached("open")
	p.record_room_reached("open")
	p.record_room_cleared("open")
	p.record_room_death("open")
	var back := _roundtrip(p)
	assert_eq([back.reached("open"), back.clears("open"), back.deaths("open")], [2, 1, 1])
	assert_eq(back.to_dict().version, Profile.VERSION)


func test_old_saves_start_reaches_at_their_clears() -> void:
	var old := {
		"version": 4,
		"met_rooms": ["open", "tide", 7],
		"room_clears": {"open": 3, "piston": 2.0, "bad": "x"},
	}
	var p := Profile.from_dict(old)
	assert_eq(p.reached("open"), 3, "every clear was reached")
	assert_eq(p.reached("piston"), 2, "a cleared room counts as met and reached")
	assert_eq(p.reached("tide"), 1, "a met room was reached at least once")
	assert_eq(p.reached("bad"), 0, "a broken count is ignored")
	assert_eq(p.deaths("open"), 0, "deaths start at 0")
	assert_eq(Profile.from_dict({}).reached("open"), 0, "a fresh save has no stats")
	# A version 5 save keeps its own reaches, even when lower than a met room's 1.
	var v5 := Profile.from_dict({"version": 5, "met_rooms": ["tide"], "room_reached": {}})
	assert_eq(v5.reached("tide"), 0, "no second migration")
	var broken := Profile.from_dict({"version": 5, "room_deaths": {"open": -4, "tide": 2}})
	assert_eq(broken.deaths("open"), 0, "negative counts are dropped")
	assert_eq(broken.deaths("tide"), 2)


func test_merge_takes_the_higher_count_and_never_doubles() -> void:
	var server := Profile.new()
	for i in 5:
		server.record_room_reached("open")
	server.record_room_cleared("open")
	server.record_room_death("open")
	server.record_room_death("tide")
	var phone := Profile.new()
	phone.record_room_reached("open")
	phone.record_room_death("open")
	phone.record_room_death("open")
	phone.record_room_reached("piston")
	var cloud := Profile.from_dict(JSON.parse_string(JSON.stringify(server.cloud_dict())))
	phone.merge_cloud(cloud, 3)
	assert_eq(phone.reached("open"), 5)
	assert_eq(phone.clears("open"), 1)
	assert_eq(phone.deaths("open"), 2, "this phone had more")
	assert_eq(phone.deaths("tide"), 1, "a room only the server had")
	assert_eq(phone.reached("piston"), 1, "a room only this phone had")
	phone.merge_cloud(cloud, 3)
	assert_eq(phone.reached("open"), 5, "merging the same copy again adds nothing")
	assert_eq(phone.deaths("open"), 2)
	assert_true(server.cloud_dict().has("room_deaths"), "stats travel to the server")


func test_room_detail_shows_stats_or_an_empty_state() -> void:
	DevMode.override = 0
	var p := Profile.new()
	for i in 4:
		p.record_room_reached("piston")
	p.record_room_cleared("piston")
	p.record_room_death("piston")
	p.record_room_death("piston")
	var screen := RoomDetailScreen.new(p, "piston")
	screen.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_eq(screen.stat_text("reached"), "4")
	assert_eq(screen.stat_text("cleared"), "1")
	assert_eq(screen.stat_text("deaths"), "2")
	assert_true(screen.shows_rate())
	assert_eq(screen.rate_text(), "25%")
	screen.free()
	# Developer mode opens a room no real run reached: it says so.
	DevMode.override = 1
	var empty := RoomDetailScreen.new(p, "tide")
	(Engine.get_main_loop() as SceneTree).root.add_child(empty)
	assert_eq(empty.stat_text("reached"), "")
	assert_false(empty.shows_rate(), "no rate without a reach")
	assert_true(empty.find_child("NoStats", true, false) != null, "the empty state shows")
	empty.free()
	DevMode.override = 0
	var locked := RoomDetailScreen.new(p, "flip")
	(Engine.get_main_loop() as SceneTree).root.add_child(locked)
	assert_eq(locked.stat_text("reached"), "", "a locked room shows why, not stats")
	assert_true(locked.find_child("NoStats", true, false) == null)
	locked.free()


func test_room_card_says_clears_of_reaches() -> void:
	DevMode.override = 0
	var p := Profile.new()
	for i in 14:
		p.record_room_reached("open")
	for i in 9:
		p.record_room_cleared("open")
	p.record_room_reached("tide")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("open")), "Cleared 9 of 14")
	assert_eq(RoomInfo.status(p, RoomCatalog.find("tide")), "Not cleared yet")
