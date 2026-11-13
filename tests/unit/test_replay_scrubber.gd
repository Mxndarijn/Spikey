extends TestCase
## The replay scrubber: a seek lands the run exactly where a straight replay
## stands (keyframes + stepping on), the run then plays on to the same end,
## and the timeline's controls fit the phone and do what they say.

const TEST_PATH := "user://test_replay_scrubber_profile.json"
const GOLDEN_DIR := "res://tests/replay/golden"


## The sim of a straight replay at `tick` (a revive due there done), as seek() gives it.
static func _straight_at(r: Replay, tick: int) -> GameSim:
	var sim := GameSim.new(r.seed_value, r.season)
	var next := 0
	var next_revive := 0
	while sim.state.tick < tick:
		if sim.is_over():
			var due := (
				next_revive < r.revive_ticks.size()
				and r.revive_ticks[next_revive] == sim.state.tick
			)
			if not due or not sim.revive():
				break
			next_revive += 1
		var tap := next < r.taps.size() and r.taps[next] == sim.state.tick
		if tap:
			next += 1
		sim.step(tap)
	if (
		sim.is_over()
		and next_revive < r.revive_ticks.size()
		and r.revive_ticks[next_revive] == sim.state.tick
	):
		sim.revive()
	return sim


static func _index_of(r: Replay) -> ReplayIndex:
	var index := ReplayIndex.new(r.seed_value, r.taps, r.season, r.revive_ticks, r.end_tick)
	while not index.build(500):
		pass
	return index


## Seeks `index` to `tick` in a controller and plays the run out from there.
static func _play_out_from(r: Replay, index: ReplayIndex, tick: int) -> RunController:
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.new(r.seed_value, r.taps, r.season, r.revive_ticks))
	rc.seek(index.seek(tick))
	while not rc.sim.is_over() and rc.sim.state.tick < SimConfig.MAX_TICKS:
		rc.advance()
	return rc


func _check_seeks(r: Replay, label: String) -> void:
	var index := _index_of(r)
	assert_eq(index.end_tick, r.end_tick, "%s: the index ends where the run did" % label)
	var ticks: Array[int] = [0, 1, 59, 60, 61, r.end_tick / 3, r.end_tick / 2, r.end_tick - 1]
	for t in r.revive_ticks:
		ticks.append_array([t - 1, t, t + 1])
	for t in ticks:
		if t < 0 or t >= r.end_tick:
			continue
		var at := index.seek(t)
		assert_eq(at.state.tick, t, "%s: seek lands on %d" % [label, t])
		assert_eq(at.checksum(), _straight_at(r, t).checksum(), "%s: same state at %d" % [label, t])
		var rc := _play_out_from(r, index, t)
		assert_eq(rc.sim.state.tick, r.end_tick, "%s: from %d, the same end tick" % [label, t])
		assert_eq(rc.sim.checksum(), r.checksum, "%s: from %d, the same final state" % [label, t])
		rc.free()


func test_seek_then_play_matches_the_golden_replays() -> void:
	var dir := DirAccess.open(GOLDEN_DIR)
	assert_true(dir != null, "golden dir exists")
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(GOLDEN_DIR.path_join(file))
		)
		var r := Replay.from_dict(data as Dictionary)
		# The run as this build plays it (the goldens may be a version behind).
		var sim := Replay.simulate(r.seed_value, r.taps, r.season, r.revive_ticks)
		r = Replay.from_sim(sim, r.taps, r.revive_ticks)
		_check_seeks(r, file)


func test_seek_then_play_matches_a_revived_run() -> void:
	var r := SimBots.play_revived(5170, SimBots.gap_seeker, 4, 700, 700)
	assert_eq(r.revive_ticks.size(), 1, "the run was revived")
	_check_seeks(r, "revived")


## Seeking back and forth on one controller: the driver's cursors follow.
func test_driver_cursors_follow_seeks() -> void:
	var r := SimBots.play(5171, SimBots.gap_seeker, 2)
	var index := _index_of(r)
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.new(r.seed_value, r.taps))
	for i in r.end_tick / 2:
		rc.advance()
	rc.seek(index.seek(r.end_tick / 5))
	for i in 30:
		rc.advance()
	rc.seek(index.seek(r.end_tick * 4 / 5))
	rc.seek(index.seek(r.end_tick / 4))
	while not rc.sim.is_over():
		rc.advance()
	assert_eq(rc.sim.checksum(), r.checksum, "back, forward and back again: the same end")
	rc.free()


func test_the_index_knows_chapters_bounces_and_coins() -> void:
	var r := SimBots.play(5172, SimBots.gap_seeker, 3)
	var index := ReplayIndex.new(r.seed_value, r.taps, r.season, r.revive_ticks, r.end_tick)
	assert_false(index.is_done(), "built a little at a time")
	assert_eq(index.length(), r.end_tick, "the claimed end until it's built")
	while not index.build(100):
		pass
	var sim := GameSim.new(r.seed_value)
	var rooms := 1
	var bounces := 0
	var coins := 0
	var next := 0
	while not sim.is_over():
		var tap := next < r.taps.size() and r.taps[next] == sim.state.tick
		if tap:
			next += 1
		sim.step(tap)
		rooms += sim.events.count(GameSim.Event.ROOM_CHANGE)
		bounces += sim.events.count(GameSim.Event.BOUNCE)
		coins += sim.events.count(GameSim.Event.COIN)
	assert_eq(index.room_starts.size(), rooms, "one chapter per room")
	assert_eq(index.room_starts[0], 0, "the first room starts at 0")
	assert_eq(index.bounces.size(), bounces, "every bounce")
	assert_eq(index.coins.size(), coins, "every coin")
	assert_true(bounces > 2, "the bot bounced")
	var b := index.bounces[2]
	assert_eq(index.bounce_after(b), index.bounces[3], "the next bounce")
	assert_eq(index.bounce_before(b + 1), index.bounces[1], "a tap just after goes one back")
	assert_eq(index.chapter_at(r.end_tick - 1), rooms - 1, "the last room at the end")
	# A seek beyond what's built stops at the frontier.
	var fresh := ReplayIndex.new(r.seed_value, r.taps)
	fresh.build(40)
	assert_eq(fresh.seek(r.end_tick - 1).state.tick, 40, "no further than it has played")


## 0.25x steps the sim every 4th frame, 2x twice a frame; the views blend in between.
func test_speeds() -> void:
	var r := SimBots.play(5173, SimBots.gap_seeker, 4)
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.new(r.seed_value, r.taps))
	rc.speed_q = 1
	for i in 8:
		rc._physics_process(0.0)
	assert_eq(rc.sim.state.tick, 2, "0.25x: a tick every 4 frames")
	assert_between(roundi(rc.blend_fraction(0.5) * 100), 10, 15, "between ticks")
	rc.speed_q = 8
	for i in 3:
		rc._physics_process(0.0)
	assert_eq(rc.sim.state.tick, 8, "2x: two ticks a frame")
	while not rc.sim.is_over():
		rc._physics_process(0.0)
	assert_eq(rc.sim.checksum(), r.checksum, "speed never changes the run")
	rc.free()


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = SampleLeaderboard.new(Profile.new())
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	# A 19.5:9 phone (360 x 780, room under a 47 px notch) or a 16:9 one.
	return main


## A 19.5:9 phone (360 x 780: the room under a 47 px notch, a 34 px home bar)
## or a 16:9 one (no room below the room).
static func _fit_phone(main: Node, tall: bool) -> void:
	var hud: Hud = main._hud
	hud.room_rect = Rect2(0, 47 if tall else 0, 360, 640)
	hud.replay_hud().scrubber().set_band_space(780.0 - 34.0 - 687.0 if tall else 0.0)


static func _run_of(r: Replay) -> Dictionary:
	return {
		"run": 3,
		"name": "Noor",
		"score": r.score,
		"gameplay_version": r.gameplay_version,
		"seed": r.seed_value,
		"taps": Array(r.taps),
		"end_tick": r.end_tick,
		"loadout": {},
	}


func test_controls_fit_a_tall_and_a_short_phone() -> void:
	for tall in [true, false]:
		var label := "tall" if tall else "16:9"
		var main := _make_main()
		var r := SimBots.play(5174, SimBots.gap_seeker, 5)
		main.play_replay(_run_of(r))
		_fit_phone(main, tall)
		var s: ReplayScrubber = main._hud.replay_hud().scrubber()
		assert_true(s.visible, "%s: the scrubber shows" % label)
		while not main._scrub.index.is_done():
			main._scrub.index.build(400)
		s._process(0.0)
		s.set_paused(true)
		var band := s.band_rect()
		if tall:
			assert_eq(band.position.y, 640.0, "tall: the band sits under the room")
			assert_true(band.size.y >= ReplayScrubber.BAND_H, "tall: the whole band fits")
		else:
			assert_eq(band.end.y, 640.0, "16:9: the band covers the room's bottom")
		for b in s.pill_buttons():
			assert_true(b.size.y >= UiTokens.SIZE_TAP_MIN, "%s: %s tall enough" % [label, b.name])
			assert_true(b.size.x >= UiTokens.SIZE_TAP_MIN, "%s: %s wide enough" % [label, b.name])
		var pill := s.pill_rect()
		var reach := float(SimConfig.SPIKE_DEPTH) / SimConfig.SUB
		assert_true(pill.position.x >= reach, "%s: the pill clears the left wall's spikes" % label)
		assert_true(pill.end.x <= 360.0 - reach, "%s: and the right wall's" % label)
		assert_true(pill.end.y <= 612.0 - 12.0, "%s: 12 px above the floor spikes" % label)
		for c in s.chip_buttons():
			assert_true(c.size.y >= UiTokens.SIZE_TAP_MIN, "%s: %s tall enough" % [label, c.name])
		# The chips' tap areas end where the track's begins.
		var chip_bottom := s._strip.position.y + s._strip.size.y
		assert_true(
			chip_bottom <= s._track.position.y + 0.5, "%s: chips and track don't overlap" % label
		)
		assert_eq(s.chip_buttons().size(), main._scrub.index.room_starts.size(), "a chip per room")
		main.free()
	SafeFile.remove(TEST_PATH)


## In the game: jump back from the end screen, then the run plays on to the
## same end; a chip jumps to its room's start; Crash -3 s lands 3 s before.
func test_scrubbing_in_the_game() -> void:
	var main := _make_main()
	var r := SimBots.play(5175, SimBots.gap_seeker, 6)
	assert_true(r.end_tick > 400, "long enough to scrub")
	main.play_replay(_run_of(r))
	_fit_phone(main, true)
	var s: ReplayScrubber = main._hud.replay_hud().scrubber()
	var rc: RunController = main._run
	while not rc.sim.is_over():
		rc.advance()
	var hud: ReplayHud = main._hud.replay_hud()
	assert_true(hud.is_over_showing(), "the end screen")
	while not main._scrub.index.is_done():
		main._scrub.index.build(400)
	s._process(0.0)
	s._jump_to_crash()
	assert_eq(rc.sim.state.tick, r.end_tick - ReplayScrubber.CRASH_LEAD, "3 s before the crash")
	assert_false(hud.is_over_showing(), "back in the run")
	assert_true(s.is_paused() and rc.paused, "paused there")
	assert_true(s.is_pill_shown() or s._pill.visible, "the controls show")
	s.toggle_pause()
	assert_false(rc.paused, "Play plays on")
	while not rc.sim.is_over():
		rc.advance()
	assert_eq(rc.sim.checksum(), r.checksum, "the same end after the jump")
	# A chapter chip jumps to its room's start.
	var index: ReplayIndex = main._scrub.index
	var last := index.room_starts.size() - 1
	s._on_chip(last)
	assert_eq(rc.sim.state.tick, index.room_starts[last], "the room's start")
	assert_eq(rc.sim.state.room_index, last, "in that room")
	# One bounce back and forward.
	var now := rc.sim.state.tick
	s._step(1)
	assert_eq(rc.sim.state.tick, index.bounce_after(now), "the next bounce")
	s._step(-1)
	assert_true(rc.sim.state.tick < index.bounce_after(now), "back one")
	# Speed cycles 1x, 2x, 0.25x, 0.5x.
	var seen: Array[int] = []
	for i in 4:
		s._cycle_speed()
		seen.append(rc.speed_q)
	assert_eq(seen, [8, 1, 2, 4] as Array[int], "speed steps")
	# Dragging the track seeks and plays on after.
	s.toggle_pause()
	assert_false(rc.paused, "playing")
	s._begin_drag(s.tick_x(r.end_tick / 2))
	assert_true(rc.paused, "a drag holds the run")
	assert_eq(rc.sim.state.tick, s.x_tick(s.tick_x(r.end_tick / 2)), "the drag's tick")
	s._end_drag()
	assert_false(rc.paused, "let go: plays on")
	main.free()
	SafeFile.remove(TEST_PATH)


## Building the index between the watched run's ticks never changes that run.
func test_index_building_never_changes_the_watched_run() -> void:
	var r := SimBots.play(5176, SimBots.gap_seeker, 7)
	var index := ReplayIndex.new(r.seed_value, r.taps, r.season, r.revive_ticks, r.end_tick)
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.new(r.seed_value, r.taps))
	while not rc.sim.is_over():
		rc.advance()
		index.build(16)
	assert_eq(rc.sim.state.tick, r.end_tick, "the same end tick")
	assert_eq(rc.sim.checksum(), r.checksum, "the same final state")
	rc.free()
