class_name RivalGhost
extends Node2D
## The rival's bird in your run (docs/DUEL_MODE.md, screen B5): the rival's
## checked run of the same seed played back on a second GameSim, in step with
## your own sim's tick, drawn in the rival's own skin and slightly see-through,
## with their name over it. Your sim and your run are never touched: this only
## reads your tick. Shown only while both birds are in the same room (a bumper
## or a boss hold can put them a room apart: then a small tag at the edge says
## where the rival is). A pill under the score says what to beat.

## How see-through the rival is (decided: their own skin, slightly see-through).
const ALPHA := 0.6
const TAG_SIZE := 13
const TAG_GAP := 26.0
const PILL_Y := 108.0

var rival_name := ""
## The rival's final score: the one to beat.
var target := 0
var _player: RunController
var _run := RunController.new()
var _bird := BirdView.new()
var _font: Font


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


## "Beat 27" until your score passes it, then "Round won!".
func pill_text() -> String:
	if _player != null and _player.sim != null and _player.sim.state.score > target:
		return "Round won!"
	return "Beat %d" % target


func _draw() -> void:
	if _run.sim == null:
		return
	var w := float(SimConfig.WORLD_W) / SimConfig.SUB
	# The pill under the score (drawn at full strength).
	var pill := pill_text()
	var pw := _font.get_string_size(pill, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
	var rect := Rect2((w - pw) / 2.0, PILL_Y, pw, 26.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
		var tag := "%s · room %d" % [rival_name, _run.sim.state.room_index + 1]
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
