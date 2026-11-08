extends TestCase
## The audio director: sounds for game events, music stems that build with the
## run, the music pick, and volume settings. Headless Godot plays audio on a
## dummy driver, so this checks what would play, not how it sounds.

const TEST_PATH := "user://test_audio_profile.json"


func _make_main() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _done(main: Node) -> void:
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_every_sound_and_stem_loads() -> void:
	for n in AudioDirector.SFX_NAMES:
		var path := "%s/%s.ogg" % [AudioDirector.SFX_DIR, n]
		assert_true(load(path) is AudioStream, "sound %s" % n)
	for t in MusicTrack.all():
		for i in MusicTrack.STEMS.size():
			assert_true(load(t.stem_path(i)) is AudioStream, "%s stem %d" % [t.id, i])
		var s := t.build_stream()
		assert_eq(s.stream_count, 4, "%s has four stems" % t.id)
		var stem := s.get_sync_stream(0) as AudioStreamOggVorbis
		assert_true(stem != null and stem.loop, "%s stems loop" % t.id)


func test_music_builds_with_the_score_and_route() -> void:
	assert_eq(AudioDirector.mood_for(0, 0), AudioDirector.Mood.START)
	assert_eq(AudioDirector.mood_for(AudioDirector.DRUMS_AT, 0), AudioDirector.Mood.PORTALS)
	assert_eq(AudioDirector.mood_for(AudioDirector.LEAD_AT, 0), AudioDirector.Mood.FULL)
	assert_eq(AudioDirector.mood_for(5, SimState.ExitKind.CALM), AudioDirector.Mood.CALM)
	assert_eq(AudioDirector.mood_for(5, SimState.ExitKind.WILD), AudioDirector.Mood.WILD)
	var start := AudioDirector.stem_targets(AudioDirector.Mood.START)
	assert_eq(start[MusicTrack.PAD], 0.0, "pad on at the start")
	assert_eq(start[MusicTrack.BASS], 0.0, "bass on at the start")
	assert_true(start[MusicTrack.DRUMS] < -30.0, "no drums yet")
	var full := AudioDirector.stem_targets(AudioDirector.Mood.FULL)
	for i in full.size():
		assert_eq(full[i], 0.0, "everything on at %d points" % AudioDirector.LEAD_AT)


func test_match_my_world_picks_the_worlds_track() -> void:
	assert_eq(MusicTrack.for_world("lava").id, "lava_rush")
	assert_eq(MusicTrack.for_world("ice").id, "bubble_drift")
	assert_eq(MusicTrack.for_world("no_such_world").id, MusicTrack.DEFAULT_ID)
	for w in ThemeCatalog.all():
		assert_true(MusicTrack.for_world(w.id) != null, "a track for %s" % w.id)


func test_game_events_play_their_sounds() -> void:
	var main := _make_main()
	var audio: AudioDirector = main._audio
	assert_true(AudioDirector.current == audio, "the app's director is current")
	assert_true(audio.track != null, "music plays from the start")
	main.start_run()
	var run: RunController = main._run
	run.flapped.emit()
	run.bounced.emit()
	run.bounced.emit()
	run.coin_collected.emit(1)
	for n in ["flap", "bounce", "coin"]:
		assert_true(n in audio.played, "%s plays" % n)
	# Bounces climb the scale, and a new room starts it again.
	var bounces: Array[float] = []
	for v in audio._voices:
		if v.stream == audio._sfx["bounce"]:
			bounces.append(v.pitch_scale)
	assert_eq(bounces.size(), 2, "two bounce voices")
	if bounces.size() == 2:
		assert_ne(bounces[0], bounces[1], "the second bounce is higher")
	run.sim.state.death_cause = SimState.DeathCause.CEILING
	run.died.emit(Replay.from_sim(run.sim, PackedInt32Array()))
	assert_true("death_wall" in audio.played, "a ceiling death bonks")
	assert_true(audio._dead, "music sinks after a death")
	main.show_home()
	assert_false(audio._dead, "menus bring the music back")
	assert_eq(audio.mood, AudioDirector.Mood.MENU)
	_done(main)


func test_buttons_click() -> void:
	var main := _make_main()
	var audio: AudioDirector = main._audio
	var b := Button.new()
	b.name = "PlayButton"
	main.add_child(b)
	b.pressed.emit()
	assert_eq(audio.played[audio.played.size() - 1], "ui_tap")
	var back := Button.new()
	back.name = "BackButton"
	main.add_child(back)
	back.pressed.emit()
	assert_eq(audio.played[audio.played.size() - 1], "ui_back")
	_done(main)


func test_volume_settings_set_the_buses() -> void:
	var main := _make_main()
	var audio: AudioDirector = main._audio
	audio.set_volumes(50, 100, true, false)
	var music := AudioServer.get_bus_index(AudioDirector.MUSIC_BUS)
	var sfx := AudioServer.get_bus_index(AudioDirector.SFX_BUS)
	assert_false(AudioServer.is_bus_mute(music), "music on")
	# Half volume is a quarter of the power: about -12 dB under the bus level.
	var db := AudioServer.get_bus_volume_db(music) - AudioDirector.MUSIC_DB
	assert_true(absf(db - linear_to_db(0.25)) < 0.1, "perceptual volume")
	assert_true(AudioServer.is_bus_mute(sfx), "sounds off")
	audio.played.clear()
	audio.play("flap")
	assert_true(audio.played.is_empty(), "nothing plays with sounds off")
	audio.set_volumes(80, 100)
	_done(main)


func test_profile_keeps_sound_settings() -> void:
	var p := Profile.new()
	p.music_volume = 35
	p.sfx_on = false
	var back := Profile.from_dict(p.to_dict())
	assert_eq(back.music_volume, 35)
	assert_false(back.sfx_on)
	var old := Profile.from_dict({"coins": 3})
	assert_eq(old.music_volume, 80, "old saves get the default")
	assert_true(old.music_on and old.sfx_on, "old saves have sound on")
