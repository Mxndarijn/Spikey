class_name RivalGhost
extends Node2D
## The rival's bird in your run (docs/DUEL_MODE.md, screen B5): the rival's
## checked run of the same seed played back on a second GameSim, in step with
## your own sim's tick, drawn in the rival's own skin and slightly see-through,
## with their name over it. Your sim and your run are never touched: this only
## reads your tick. Shown only while both birds are in the same room (a bumper
## or a boss hold can put them a room apart: then a small tag at the edge says
## where the rival is). A pill under the score says what to beat.
##
## Live (Duel, screen D3): the rival's taps arrive as they are made
## (`feed`, from the Duel socket), so the rival is drawn a little behind your
## own tick: `delay_ticks`, a jitter buffer of 100 to 500 ms that follows how
## late the rival's batches come (about 150 to 250 ms on a good connection).
## It never runs past the last tick the rival confirmed: when data is late the
## rival holds, then catches up.

## How see-through the rival is (decided: their own skin, slightly see-through).
const ALPHA := 0.6
const TAG_SIZE := 13
const TAG_GAP := 26.0
const PILL_Y := 108.0
## The live jitter buffer, ticks: 100 ms to 500 ms, 200 ms to start.
const DELAY_MIN := 6
const DELAY_MAX := 30
const DELAY_START := 12
## How many recent batches the buffer looks at.
const LATE_WINDOW := 30

var rival_name := ""
## The rival's final score: the one to beat.
var target := 0
## Live: taps arrive with `feed`; the rival never passes `confirmed`.
var live := false
var confirmed := -1
var delay_ticks := DELAY_START
## Live: the rival is down at this score (-1: still flying).
var down_score := -1
var _player: RunController
var _run := RunController.new()
var _bird := BirdView.new()
var _font: Font
var _late: Array[int] = []


## `run`: the rival's checked run (BattleView.rival). `character`: their flyer.
func _init(run: Dictionary, character: CharacterDef, p_name: String) -> void:
	rival_name = p_name
	target = int(run.get("score", 0))
	modulate.a = ALPHA
	_font = GameFonts.ui(800)
	_run.new_replay(ReplayDriver.from_run(run, int(run.get("season", Seasons.NONE))))
	_run.paused = true
	_bird.name = "RivalBird"
	add_child(_bird)
	_bird.bind(_run, character)
	_run.flapped.connect(_bird.on_flap)
	_run.bounced.connect(_bird.on_bounce)
	_run.died.connect(func(_r: Replay) -> void: _bird.on_death())


## A live rival (Duel): the round's seed and season; taps come with `feed`.
static func live_on(
	seed_value: int, season: int, character: CharacterDef, p_name: String
) -> RivalGhost:
	var g := RivalGhost.new({"seed": seed_value, "season": season, "taps": []}, character, p_name)
	g.live = true
	g.target = 0
	return g


## Live: the rival reached tick `tick` with these taps since the last batch.
func feed(tick: int, taps: Array) -> void:
	var driver := _run.driver
	for t: Variant in taps:
		driver.taps.append(int(t))
	confirmed = maxi(confirmed, tick)
	if _player != null and _player.sim != null:
		# How far behind your own tick the rival's news is: the buffer covers most.
		_late.append(maxi(_player.sim.state.tick - tick, 0))
		if _late.size() > LATE_WINDOW:
			_late.pop_front()
		var sorted := _late.duplicate()
		sorted.sort()
		var p95: int = sorted[int((sorted.size() - 1) * 0.95)]
		delay_ticks = clampi(p95 + 6, DELAY_MIN, DELAY_MAX)


## Live: the server says the rival is down.
func set_down(score: int) -> void:
	down_score = score
	target = score


## Follows `player`'s run from now on.
func follow(player: RunController) -> void:
	_player = player


func _exit_tree() -> void:
	if is_instance_valid(_run):
		_run.queue_free()


func _physics_process(_delta: float) -> void:
	if _player == null or _player.sim == null or _run.sim == null:
		return
	# Never ahead of your bird, never behind: the same tick of the same map.
	var to := _player.sim.state.tick
	if live:
		# A little behind, and never past what the rival confirmed.
		to = mini(to - delay_ticks, confirmed)
	while _run.sim.state.tick < to and not _run.sim.is_over():
		_run.advance()


func _process(_delta: float) -> void:
	_bird.visible = same_room()
	queue_redraw()


## Both birds in the same room (the rival's walls are yours).
func same_room() -> bool:
	if _player == null or _player.sim == null or _run.sim == null:
		return false
	return _player.sim.state.room_index == _run.sim.state.room_index


func rival_sim() -> GameSim:
	return _run.sim


func bird() -> BirdView:
	return _bird


## "Beat 27" until your score passes it, then "Round won!". Live: only once
## the rival is down ("" before).
func pill_text() -> String:
	if live and down_score < 0:
		return ""
	if _player != null and _player.sim != null and _player.sim.state.score > target:
		return "Round won!"
	return "Beat %d" % target


func _draw() -> void:
	if _run.sim == null:
		return
	var w := float(SimConfig.WORLD_W) / SimConfig.SUB
	# The pill under the score (drawn at full strength).
	var pill := pill_text()
	if not pill.is_empty():
		_draw_pill(pill, w)
	var label := "%s %d" % [rival_name, _run.sim.state.score]
	if same_room():
		var at := _bird.position + Vector2(0, -TAG_GAP)
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		draw_string(
			_font,
			at - Vector2(lw / 2.0, 0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			TAG_SIZE,
			UiTokens.ON_SKY
		)
	else:
		var tag := "%s · Room %d" % [rival_name, _run.sim.state.room_index + 1]
		var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		draw_string(
			_font,
			Vector2(w - tw - 12.0, PILL_Y + 48.0),
			tag,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			TAG_SIZE,
			UiTokens.ON_SKY
		)


func _draw_pill(pill: String, w: float) -> void:
	var pw := _font.get_string_size(pill, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
	var rect := Rect2((w - pw) / 2.0, PILL_Y, pw, 26.0)
	draw_rect(rect, Color(UiTokens.SCRIM, UiTokens.SCRIM.a / ALPHA))
	draw_string(
		_font,
		rect.position + Vector2(12, 18),
		pill,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(UiTokens.ON_SCRIM, 1.0 / ALPHA)
	)
