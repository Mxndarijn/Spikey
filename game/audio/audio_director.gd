class_name AudioDirector
extends Node
## Plays every sound and the background music. It listens to the run's
## signals and reads sim state, and never changes either. See docs/AUDIO.md.
##
## Sounds: a small pool of players on the SFX and UI buses, with a cap per
## sound so fast taps don't pile up. Music: the chosen MusicTrack's four stems
## in sync; stems fade in and out as the run builds (LAYERS).
##
## Menus and screens play UI sounds with AudioDirector.ui("tap") etc.; it does
## nothing when there is no director (tests, tools).

## Music moments (see LAYERS).
enum Mood { MENU, START, PORTALS, FULL, CALM, WILD }

const SFX_DIR := "res://assets/audio/sfx"
const SFX_NAMES: Array[String] = [
	"flap",
	"bounce",
	"coin",
	"coin_counter",
	"death_spike",
	"death_wall",
	"portal_open",
	"fork_appear",
	"portal_pass",
	"fork_calm",
	"fork_wild",
	"new_room",
	"milestone",
	"ui_tap",
	"ui_back",
	"ui_confirm",
	"ui_locked",
	"purchase",
	"revive",
]
const VOICES := 10
const HISTORY := 32
## Most copies of one sound playing at once.
const MAX_SAME := 2
## Bounce pitch climbs this major-pentatonic scale (semitones) per bounce in a
## room, then holds; a new room starts it again.
const BOUNCE_STEPS: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16]
const FLAP_PITCH_JITTER := 0.04
## The exit ghost replays the portal sound this much higher, as a hint.
const GHOST_PITCH := 1.6

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"
## Bus levels at full volume (dB).
const MUSIC_DB := -6.0
const SFX_DB := 0.0
const UI_DB := -2.0
## Stem fade time (s) and how quiet a muted stem gets (dB).
const FADE_TIME := 0.4
const SILENT_DB := -60.0
## After a death the music sinks under a low-pass filter.
const DEATH_CUTOFF := 400.0
const OPEN_CUTOFF := 20000.0
const DEATH_DB := -5.0

## Music moments: which stems are on [pad, bass, drums, lead] and the extra
## volume (dB), see LAYERS.
const LAYERS := {
	Mood.MENU: [[true, false, false, true], -4.0],
	Mood.START: [[true, true, false, false], 0.0],
	Mood.PORTALS: [[true, true, true, false], 0.0],
	Mood.FULL: [[true, true, true, true], 0.0],
	Mood.CALM: [[true, true, false, true], -1.0],
	Mood.WILD: [[true, true, true, true], 1.0],
}
## Score at which the drums, then the lead, join in.
const DRUMS_AT := 10
const LEAD_AT := 25

## The director the game is using (null in tests and tools).
static var current: AudioDirector

## The best score before this run: beating it plays "milestone" once.
var best_score := 0
## Track playing now (null before music starts).
var track: MusicTrack
var mood := Mood.MENU
## The latest sounds started, newest last (for tests; keeps HISTORY).
var played := PackedStringArray()

var _run: RunController
var _sfx := {}
var _voices: Array[AudioStreamPlayer] = []
var _music := AudioStreamPlayer.new()
var _stream: AudioStreamSynchronized
## Per stem: volume now and where it is heading (dB).
var _stem_db := PackedFloat32Array()
var _stem_target := PackedFloat32Array()
var _mood_db := 0.0
var _bounce_step := 0
var _beat_best := false
var _dead := false
var _filter: AudioEffectLowPassFilter
var _music_on := true
var _sfx_on := true
var _music_volume := 100
var _sfx_volume := 100
var _rng := RandomNumberGenerator.new()


static func ui(sound: String) -> void:
	if current != null:
		current.play("ui_" + sound)


## Plays a non-UI sound from anywhere (shop purchase, revive...).
static func sound(sound_name: String) -> void:
	if current != null:
		current.play(sound_name)


func _ready() -> void:
	current = self
	_setup_buses()
	for n in SFX_NAMES:
		_sfx[n] = load("%s/%s.ogg" % [SFX_DIR, n])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_music.bus = MUSIC_BUS
	add_child(_music)
	_stem_db.resize(MusicTrack.STEMS.size())
	_stem_target.resize(MusicTrack.STEMS.size())
	_stem_db.fill(SILENT_DB)
	_stem_target.fill(SILENT_DB)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons(get_tree().root)


func _exit_tree() -> void:
	if current == self:
		current = null


## Listens to a run's events.
func bind(run: RunController) -> void:
	_run = run
	run.run_started.connect(_on_run_started)
	run.flapped.connect(_on_flapped)
	run.bounced.connect(_on_bounced)
	run.scored.connect(_on_scored)
	run.room_changed.connect(_on_room_changed)
	run.exit_opened.connect(_on_exit_opened)
	run.exit_previewed.connect(_on_exit_previewed)
	run.coin_collected.connect(func(_total: int) -> void: play("coin"))
	run.died.connect(_on_died)
	run.revived.connect(_on_revived)


## Settings: volumes 0..100 (perceptual: gain = (v / 100)^2) and on/off.
func set_volumes(music: int, sfx: int, music_on: bool = true, sfx_on: bool = true) -> void:
	_music_volume = clampi(music, 0, 100)
	_sfx_volume = clampi(sfx, 0, 100)
	_music_on = music_on
	_sfx_on = sfx_on
	_apply_volumes()


## Picks the music: a track id, MusicTrack.MATCH_WORLD or MusicTrack.SHUFFLE.
## `world_id` is the equipped world (for Match my world); `owned` the owned
## track ids (for Shuffle). Keeps playing if it is already the same track.
func choose_track(pick: String, world_id: String, owned: PackedStringArray = []) -> void:
	var t: MusicTrack
	if pick == MusicTrack.SHUFFLE and not owned.is_empty():
		t = MusicTrack.find(owned[_rng.randi_range(0, owned.size() - 1)])
	elif pick != MusicTrack.MATCH_WORLD and pick != MusicTrack.SHUFFLE:
		t = MusicTrack.find(pick)
	if t == null:
		t = MusicTrack.for_world(world_id)
	play_track(t)


## Starts `t` from the top (unless it is already playing) in the current mood.
func play_track(t: MusicTrack) -> void:
	if t == null or (track != null and track.id == t.id and _music.playing):
		return
	track = t
	_stream = t.build_stream()
	_music.stream = _stream
	_stem_db.fill(SILENT_DB)
	_set_mood(mood, true)
	_music.play()


## Back to the menus: quieter music without bass and drums, no filter.
func menu() -> void:
	_dead = false
	_set_mood(Mood.MENU)


## Plays a sound by name (see SFX_NAMES). `pitch` 1 = as recorded.
func play(sound_name: String, pitch: float = 1.0) -> void:
	var stream: AudioStream = _sfx.get(sound_name)
	if stream == null or not _sfx_on or _sfx_volume == 0:
		return
	var same := 0
	var free: AudioStreamPlayer = null
	var oldest: AudioStreamPlayer = null
	for p in _voices:
		if p.playing and p.stream == stream:
			same += 1
			if oldest == null or p.get_playback_position() > oldest.get_playback_position():
				oldest = p
		elif not p.playing and free == null:
			free = p
	var voice := oldest if same >= MAX_SAME else free
	if voice == null:
		return
	voice.stream = stream
	voice.bus = UI_BUS if sound_name.begins_with("ui_") else SFX_BUS
	voice.pitch_scale = pitch
	voice.play()
	played.append(sound_name)
	if played.size() > HISTORY:
		played.remove_at(0)


## The stems' target volumes (dB) for a mood, for tests.
static func stem_targets(m: Mood) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var layer: Array = LAYERS[m]
	for on: bool in layer[0]:
		out.append(0.0 if on else SILENT_DB)
	return out


## The mood for a run at `score` with `route` (SimState.ExitKind).
static func mood_for(score: int, route: int) -> Mood:
	if route == SimState.ExitKind.CALM:
		return Mood.CALM
	if route == SimState.ExitKind.WILD:
		return Mood.WILD
	if score >= LEAD_AT:
		return Mood.FULL
	if score >= DRUMS_AT:
		return Mood.PORTALS
	return Mood.START


func _process(delta: float) -> void:
	if _stream == null:
		return
	var step := (0.0 - SILENT_DB) * delta / FADE_TIME
	for i in _stem_db.size():
		_stem_db[i] = move_toward(_stem_db[i], _stem_target[i], step)
		_stream.set_sync_stream_volume(i, _stem_db[i] + _mood_db)
	var cutoff := DEATH_CUTOFF if _dead else OPEN_CUTOFF
	_filter.cutoff_hz = lerpf(_filter.cutoff_hz, cutoff, minf(delta * 6.0, 1.0))


func _set_mood(m: Mood, instant: bool = false) -> void:
	mood = m
	_stem_target = stem_targets(m)
	_mood_db = float(LAYERS[m][1]) + (DEATH_DB if _dead else 0.0)
	if instant:
		_stem_db = _stem_target.duplicate()


func _on_run_started() -> void:
	_dead = false
	_bounce_step = 0
	_beat_best = false
	_set_mood(Mood.START)


func _on_flapped() -> void:
	play("flap", 1.0 + _rng.randf_range(-1.0, 1.0) * FLAP_PITCH_JITTER)


func _on_bounced() -> void:
	var semis := BOUNCE_STEPS[mini(_bounce_step, BOUNCE_STEPS.size() - 1)]
	_bounce_step += 1
	play("bounce", pow(2.0, semis / 12.0))


func _on_scored(score: int) -> void:
	if not _beat_best and best_score > 0 and score > best_score:
		_beat_best = true
		play("milestone")
	var route := _run.sim.state.route if _run != null and _run.sim != null else 0
	var m := mood_for(score, route)
	if m != mood:
		_set_mood(m)


func _on_exit_opened() -> void:
	var s := _run.sim.state
	play("fork_appear" if s.exit_b_kind != SimState.ExitKind.NORMAL else "portal_open")


## The ghost of the next exit: a soft, high hint of the portal sound.
func _on_exit_previewed() -> void:
	play("portal_open", GHOST_PITCH)


func _on_room_changed(room_index: int) -> void:
	_bounce_step = 0
	if room_index <= 0 or _run == null or _run.sim == null:
		return
	var s := _run.sim.state
	# A fork exit keeps its kinds in the state after the bird goes through.
	var fork := s.exit_b_kind != SimState.ExitKind.NORMAL
	if fork and s.route == SimState.ExitKind.CALM:
		play("fork_calm")
	elif fork and s.route == SimState.ExitKind.WILD:
		play("fork_wild")
	else:
		play("portal_pass")
	play("new_room")
	_set_mood(mood_for(s.score, s.route))


func _on_died(_replay: Replay) -> void:
	var cause := _run.sim.state.death_cause if _run != null and _run.sim != null else 0
	var edge := cause in [SimState.DeathCause.CEILING, SimState.DeathCause.FLOOR]
	play("death_wall" if edge else "death_spike")
	_dead = true
	_set_mood(mood)


## Back from a crash: the revive sound, and the music opens up again.
func _on_revived() -> void:
	play("revive")
	_dead = false
	_bounce_step = 0
	_set_mood(mood)


## Every button in the game clicks: back and close buttons with a falling pop,
## the rest with a rising one. Screens play confirm, locked and purchase
## sounds themselves.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)


func _hook_buttons(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)
	for child in node.get_children():
		_hook_buttons(child)


func _hook_button(b: BaseButton) -> void:
	var cb := _on_button.bind(b)
	if not b.pressed.is_connected(cb):
		b.pressed.connect(cb)


## Back, close and home buttons (UiKit.mark_back) pop down, the rest up.
func _on_button(b: BaseButton) -> void:
	play("ui_back" if b.is_in_group(UiKit.BACK_GROUP) else "ui_tap")


func _setup_buses() -> void:
	for n in [MUSIC_BUS, SFX_BUS, UI_BUS]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")
	var music := AudioServer.get_bus_index(MUSIC_BUS)
	for e in AudioServer.get_bus_effect_count(music):
		if AudioServer.get_bus_effect(music, e) is AudioEffectLowPassFilter:
			_filter = AudioServer.get_bus_effect(music, e)
	if _filter == null:
		_filter = AudioEffectLowPassFilter.new()
		_filter.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(music, _filter)


func _apply_volumes() -> void:
	_set_bus(MUSIC_BUS, MUSIC_DB, _music_volume, _music_on)
	_set_bus(SFX_BUS, SFX_DB, _sfx_volume, _sfx_on)
	_set_bus(UI_BUS, UI_DB, _sfx_volume, _sfx_on)


static func _set_bus(bus: String, base_db: float, volume: int, on: bool) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var gain := pow(volume / 100.0, 2.0)
	AudioServer.set_bus_mute(i, not on or volume == 0)
	AudioServer.set_bus_volume_db(i, base_db + linear_to_db(maxf(gain, 0.0001)))
