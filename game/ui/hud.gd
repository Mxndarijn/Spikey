class_name Hud
extends CanvasLayer
## The overlay UI of a run, in the minimal kit (no boxes):
##   Ready:     "Tap to flap" with the tap icon, on the room, and a bare back
##              arrow top left (where pause goes): Home, or Rooms in practice.
##              The first flap swaps it for the pause button.
##   Running:   a bare pause icon top left, the score big at the top, the run's
##              coins top right.
##   Paused:    the dimmed room with "Paused", the score, Music and Sounds
##              toggle circles, the round Resume, and Home ("Ends this run").
##   Crashed:   the revive offer (ReviveOffer) on the dimmed room, when the
##              run has its revive left: Revive (free, or for an ad) or Skip.
##   Game over: "Game over", the score, "Best 92", a stats row (+coins, rooms
##              cleared this run, today's rank) and the Game over dock (Home,
##              Rooms | Again | #rank, Style). A new best gets the gold ribbon,
##              the score counting up, three sparkles and confetti that falls
##              through once (still with reduced motion).
## Practice runs add PracticeHud (banner, restart, crash screen); watching a
## leaderboard run adds ReplayHud (banner, exit, result) and hides the pause
## button, coins and "Tap to flap".
## Taps outside buttons pass through to Main as flaps.

signal pause_pressed
signal play_again_pressed
signal home_pressed
## Practice: restart the room, or leave for the Rooms screen. Game over's dock
## uses rooms_pressed too.
signal restart_pressed
signal rooms_pressed
## Game over's dock: the leaderboards and Customize.
signal leaderboard_pressed
signal style_pressed
## Paused: a Music or Sounds circle was tapped ("music" or "sfx").
signal sound_toggled(which: String, on: bool)
## Replay: watch the same run again, or leave for the leaderboards
## (replay_hud() sets the run and shows its result).
signal replay_again_pressed
signal replay_back_pressed

const TOAST_SECONDS := 1.2
const COIN_ICON := preload("res://assets/ui/coin.svg")
const PAUSE_ICON := preload("res://assets/ui/icons/pause.svg")
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const TAP_ICON := preload("res://assets/ui/icons/tap.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const HOME_ICON := preload("res://assets/ui/icons/home.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const MUSIC_ICON := preload("res://assets/ui/icons/music.svg")
const SOUND_ICON := preload("res://assets/ui/icons/sound.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
## A collected coin flies from the room into the coin counter (top right).
const FLY_TIME := 0.5
const FLY_SIZE := 28.0
## How high the flight curves above the straight line, in px.
const FLY_ARC := 60.0
## The new-best score counts up over this long.
const COUNT_TIME := 1.1
## Stops redrawing the new-best moment after this.
const FX_TIME := 2.6
const TOGGLE := 56.0
## The stats row stays inside 54..306 px, clear of a crashed flyer lying on
## either wall (it can come to rest at any height).
const STAT_W := 80.0
const STAT_GAP := 6
const WALL_CLEAR := 54.0

## Settings > Reduced flashing: the new-best moment stays still.
var reduced_motion := false
## The room on screen (ScreenLayout); the HUD is laid out over it. Main sets
## it when the screen changes shape.
## The revive offer after a crash. Main shows it (show_offer) and listens to
## its Revive and Skip; the HUD clears the running HUD from under it.
var revive_offer := ReviveOffer.new()
var room_rect := Rect2(Vector2.ZERO, ScreenLayout.ROOM):
	set(value):
		room_rect = value
		if _root != null:
			_apply_room_rect()

var _run: RunController
var _toast_tween: Tween
var _coin_tween: Tween
var _run_coins := CoinPill.new()
var _practice := PracticeHud.new()
var _practicing := false
var _replay := ReplayHud.new()
var _replaying := false
var _pause_button: Button
var _back_button: Button
var _score := Label.new()
var _hint := VBoxContainer.new()
var _toast := Label.new()
var _paused := ColorRect.new()
var _paused_score := Label.new()
var _toggles := {}
var _paused_home: Control
var _game_over := Control.new()
var _go_caption := Label.new()
var _final_score := Label.new()
var _best_score := Label.new()
var _stats := HBoxContainer.new()
## The run's seed in small text, so a player can report a run that looked wrong.
var _seed := Label.new()
## "Revived at 63" under the best score, when the run used its revive.
var _revived_line := HBoxContainer.new()
var _revived_icon := TextureRect.new()
var _revived_text := Label.new()
var _stat_coins: Label
var _stat_rooms: Label
var _stat_rank: Label
var _dock: Dock
var _new_best := NewBestFx.new()
var _final_value := 0
var _go_time := -1.0
var _daily_rank := 0

@onready var _root: Control = $Root


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_room_rect()
	_build_running()
	_build_hint()
	_build_paused()
	_build_game_over()
	_root.add_child(_practice)
	_practice.restart_pressed.connect(restart_pressed.emit)
	_practice.rooms_pressed.connect(rooms_pressed.emit)
	_root.add_child(_replay)
	_replay.again_pressed.connect(replay_again_pressed.emit)
	_replay.back_pressed.connect(replay_back_pressed.emit)
	_replay.changed.connect(_on_replay_changed)
	_root.add_child(revive_offer)
	revive_offer.shown.connect(_on_revive_offer_shown)
	_toast.theme_type_variation = &"SkyLabel"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_right = 1.0
	_toast.offset_top = 124
	_toast.offset_bottom = 152
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)
	show_ready()


## Frees parts built in the member list that never joined the tree.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for n: Node in [
		_run_coins,
		_practice,
		_replay,
		revive_offer,
		_score,
		_hint,
		_toast,
		_paused,
		_game_over,
		_new_best,
		_revived_line,
		_revived_icon,
		_revived_text,
	]:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()


## The run whose score the HUD shows.
func bind_run(run: RunController) -> void:
	_run = run


func _process(delta: float) -> void:
	if _run != null and _run.sim != null and _score.visible:
		_score.text = str(RoomView.practice_points(_run.sim))
	if _go_time >= 0.0 and _game_over.visible and _new_best.visible:
		_go_time += delta
		_step_new_best()


func _build_running() -> void:
	_pause_button = UiKit.icon_button(PAUSE_ICON, "Pause")
	_pause_button.name = "Pause"
	_pause_button.position = Vector2(10, 42)
	_pause_button.add_theme_constant_override("icon_max_width", 24)
	_pause_button.pressed.connect(pause_pressed.emit)
	_root.add_child(_pause_button)
	# Same spot and size as pause, so the corner stays put after the first flap.
	_back_button = UiKit.icon_button(BACK_ICON, "Home")
	_back_button.name = "Back"
	_back_button.position = _pause_button.position
	_back_button.add_theme_constant_override("icon_max_width", 24)
	_back_button.pressed.connect(_on_back)
	_root.add_child(_back_button)
	_score.theme_type_variation = &"RoomScore"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.anchor_right = 1.0
	_score.offset_top = 34
	_score.offset_bottom = 34 + UiTheme.RUN_SCORE_SIZE + 6
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score.text = "0"
	_root.add_child(_score)
	_root.add_child(_run_coins)
	# Pinned top right, growing leftward as the number gets longer.
	_run_coins.anchor_left = 1.0
	_run_coins.anchor_right = 1.0
	_run_coins.offset_left = -18
	_run_coins.offset_right = -18
	_run_coins.offset_top = 54
	_run_coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_run_coins.set_amount(0)


## Ready's back arrow: Home, or back to Rooms in practice.
func _on_back() -> void:
	if _practicing:
		rooms_pressed.emit()
	else:
		home_pressed.emit()


func _build_hint() -> void:
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint.add_theme_constant_override("separation", 6)
	_hint.anchor_right = 1.0
	_hint.offset_top = 400
	_hint.offset_bottom = 470
	var icon := TextureRect.new()
	icon.texture = TAP_ICON
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.name = "TapIcon"
	_hint.add_child(icon)
	_hint.add_child(UiKit.label("Tap to flap", &"SkyLabel"))
	_root.add_child(_hint)


func _build_paused() -> void:
	_paused.color = UiTokens.SCRIM
	ScrimBleed.attach(_paused)
	_paused.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paused.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_paused)
	_at(_paused, UiKit.label("Paused", &"ScrimTitle"), 88)
	_paused_score.theme_type_variation = &"ScrimScore"
	_paused_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_paused, _paused_score, 146)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.add_child(_toggle("music", MUSIC_ICON))
	row.add_child(_toggle("sfx", SOUND_ICON))
	_at(_paused, row, 260)
	var resume := UiKit.primary(PLAY_ICON, "Resume", true)
	resume.name = "Resume"
	resume.anchor_left = 0.5
	resume.anchor_right = 0.5
	resume.offset_left = -UiKit.PRIMARY / 2.0
	resume.offset_right = UiKit.PRIMARY / 2.0
	resume.offset_top = 380
	resume.offset_bottom = 380 + UiKit.PRIMARY
	resume.pressed.connect(pause_pressed.emit)
	_paused.add_child(resume)
	_paused_home = _scrim_link(HOME_ICON, "Home", "Ends this run")
	(_paused_home.get_child(0) as Button).pressed.connect(home_pressed.emit)
	_at(_paused, _paused_home, 500)


## A Music or Sounds circle: paper with an ink icon when on, faint when off.
func _toggle(which: String, icon: Texture2D) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(72, 0)
	var b := Button.new()
	b.name = which
	b.toggle_mode = true
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(TOGGLE, TOGGLE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var off := UiTheme.flat(Color(1, 1, 1, 0.18), UiTokens.RADIUS_PILL, 0)
	var on := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover"]:
		b.add_theme_stylebox_override(state, off)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_constant_override("icon_max_width", 24)
	for state in ["icon_normal_color", "icon_hover_color"]:
		b.add_theme_color_override(state, UiTokens.ON_SCRIM)
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	col.add_child(b)
	var l := UiKit.label("", &"ScrimLabel")
	l.add_theme_font_size_override("font_size", 13)
	col.add_child(l)
	b.toggled.connect(_on_toggle.bind(which))
	_toggles[which] = b
	return col


func _on_toggle(on: bool, which: String) -> void:
	_show_toggle(which)
	sound_toggled.emit(which, on)


func _show_toggle(which: String) -> void:
	var b := _toggles[which] as Button
	var l := b.get_parent().get_child(1) as Label
	l.text = (
		"%s %s" % ["Music" if which == "music" else "Sounds", "on" if b.button_pressed else "off"]
	)
	b.tooltip_text = l.text


## A bare white button with an icon and text, and a small note under it.
func _scrim_link(icon: Texture2D, text: String, note: String = "") -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	var b := Button.new()
	b.theme_type_variation = &"ScrimButton"
	b.text = text
	b.icon = icon
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_constant_override("icon_max_width", 20)
	col.add_child(b)
	if not note.is_empty():
		var n := UiKit.label(note, &"ScrimCaption")
		n.add_theme_font_size_override("font_size", 12)
		col.add_child(n)
	return col


func _build_game_over() -> void:
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_game_over)
	_game_over.add_child(_new_best)
	_go_caption.theme_type_variation = &"SkyLabel"
	_go_caption.text = "Game over"
	_go_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_game_over, _go_caption, 104)
	_final_score.theme_type_variation = &"RoomBigScore"
	_final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_final_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_game_over, _final_score, 122)
	_best_score.theme_type_variation = &"SkyCaption"
	_best_score.add_theme_font_size_override("font_size", 16)
	_best_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_game_over, _best_score, 274)
	_revived_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_revived_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revived_line.add_theme_constant_override("separation", 5)
	_revived_icon.texture = HEART_ICON
	_revived_icon.custom_minimum_size = Vector2(14, 14)
	_revived_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_revived_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_revived_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_revived_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revived_line.add_child(_revived_icon)
	_revived_text.theme_type_variation = &"RoomMuted"
	_revived_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revived_line.add_child(_revived_text)
	_at(_game_over, _revived_line, 300)
	_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.add_theme_constant_override("separation", STAT_GAP)
	_stat_coins = _stat(_stats, "coins", COIN_ICON)
	_stat_rooms = _stat(_stats, "rooms")
	_stat_rank = _stat(_stats, "today")
	_at(_game_over, _stats, 330)
	_seed.theme_type_variation = &"RoomMuted"
	_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_game_over, _seed, 400)
	_dock = (
		Dock
		. new(
			[
				{"id": "home", "icon": HOME_ICON, "text": "Home"},
				{"id": "rooms", "icon": ROOMS_ICON, "text": "Rooms"},
			],
			[
				{"id": "rank", "icon": TROPHY_ICON, "text": "Ranks", "tip": "Leaderboards"},
				{"id": "style", "icon": STYLE_ICON, "text": "Style"},
			],
			{"id": "again", "icon": RESTART_ICON, "text": "Again"}
		)
	)
	_dock.pressed.connect(_on_dock)
	_game_over.add_child(_dock)


## One stat: a big number (with an icon) over a small word.
func _stat(row: HBoxContainer, word: String, icon: Texture2D = null) -> Label:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(STAT_W, 0)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	if icon != null:
		var pic := TextureRect.new()
		pic.texture = icon
		pic.custom_minimum_size = Vector2(20, 20)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(pic)
	var value := UiKit.label("", &"RoomStat")
	line.add_child(value)
	col.add_child(line)
	col.add_child(UiKit.label(word, &"RoomMuted"))
	row.add_child(col)
	return value


func _on_dock(id: String) -> void:
	match id:
		"again":
			play_again_pressed.emit()
		"home":
			home_pressed.emit()
		"rooms":
			rooms_pressed.emit()
		"rank":
			leaderboard_pressed.emit()
		"style":
			style_pressed.emit()


## Puts `c` across the parent's width at `top` px.
static func _at(parent: Control, c: Control, top: float) -> void:
	parent.add_child(c)
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = top
	c.offset_bottom = top + c.get_combined_minimum_size().y


## Updates the run's coin counter and gives it a little bump.
func set_run_coins(total: int) -> void:
	_run_coins.set_amount(total)
	_run_coins.pivot_offset = _run_coins.size / 2.0
	if total > 0 and is_inside_tree():
		AudioDirector.sound("coin_counter")
		if _coin_tween != null:
			_coin_tween.kill()
		_run_coins.scale = Vector2(1.25, 1.25)
		_coin_tween = create_tween()
		_coin_tween.tween_property(_run_coins, "scale", Vector2.ONE, 0.2)


## Sends a coin from `from` (room position) into the counter; the counter
## shows `total` when it lands. Looks only: the coin is already counted in sim/.
func fly_coin(from: Vector2, total: int) -> void:
	var coin := TextureRect.new()
	coin.texture = COIN_ICON
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(FLY_SIZE, FLY_SIZE)
	coin.pivot_offset = coin.size / 2.0
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.add_child(coin)
	var start := from - coin.size / 2.0
	var end := _counter_target() - coin.size / 2.0
	var bend := (start + end) / 2.0 + Vector2(0, -FLY_ARC)
	coin.position = start
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_method(_fly_step.bind(coin, start, bend, end), 0.0, 1.0, FLY_TIME)
	t.tween_callback(_land_coin.bind(coin, total))


## Where flying coins land: the coin icon inside the counter, in room px.
func _counter_target() -> Vector2:
	var r := _run_coins.get_global_rect()
	r.position -= _root.get_global_rect().position
	return Vector2(r.position.x + CoinPill.ICON_SIZE / 2.0, r.position.y + r.size.y / 2.0)


func _apply_room_rect() -> void:
	_root.position = room_rect.position
	_root.size = room_rect.size


static func _fly_step(t: float, coin: Control, start: Vector2, bend: Vector2, end: Vector2) -> void:
	# A curve through `bend`, shrinking a little as it reaches the counter.
	coin.position = start.lerp(bend, t).lerp(bend.lerp(end, t), t)
	coin.scale = Vector2.ONE * lerpf(1.0, 0.7, t)


func _land_coin(coin: Control, total: int) -> void:
	coin.queue_free()
	set_run_coins(total)


## Coins still on their way to the counter.
func flying_coins() -> int:
	var n := 0
	for c in _root.get_children():
		if (
			c is TextureRect
			and (c as TextureRect).texture == COIN_ICON
			and not c.is_queued_for_deletion()
		):
			n += 1
	return n


func run_coins_text() -> String:
	return _run_coins.amount_text()


## The world's theme: white room text on night rooms.
func set_room_theme(t: Theme) -> void:
	if _root != null:
		_root.theme = t


## Settings > Large buttons: the pause and back buttons grow to 56px.
func set_large_buttons(on: bool) -> void:
	var s := UiKit.LARGE_BUTTON if on else UiKit.ICON_BUTTON
	for b: Button in [_pause_button, _back_button]:
		if b != null:
			b.custom_minimum_size = Vector2(s, s)
			b.size = Vector2(s, s)
	_practice.set_large_buttons(on)
	_replay.set_large_buttons(on)


## Hides everything (a menu screen is showing).
func show_menu() -> void:
	set_practice("")
	_replay.set_run("", 0)
	show_ready()
	_hint.visible = false
	_back_button.visible = false


## Practice mode for this room name; an empty name goes back to real runs.
func set_practice(room_name: String) -> void:
	_practicing = not room_name.is_empty()
	_practice.set_room(room_name)
	_place_score()


## The practice or replay banner sits at the top; the score goes under it.
func _place_score() -> void:
	var banner := _practicing or _replaying
	_score.offset_top = 92 if banner else 34
	_score.offset_bottom = _score.offset_top + UiTheme.RUN_SCORE_SIZE + 6
	_score.add_theme_font_size_override("font_size", 64 if banner else UiTheme.RUN_SCORE_SIZE)


## The replay banner and result. Its set_run() starts or ends replay mode.
func replay_hud() -> ReplayHud:
	return _replay


## Replay mode follows the ReplayHud; its result screen covers the run's HUD.
func _on_replay_changed() -> void:
	_replaying = _replay.visible
	_place_score()
	if _replay.is_over_showing():
		_hint.visible = false
		_pause_button.visible = false
		_back_button.visible = false
		_run_coins.visible = false
		_score.visible = false


func is_practicing() -> bool:
	return _practicing


func practice_hud() -> PracticeHud:
	return _practice


## A practice run crashed: this try's points, Try again and Back to rooms.
func show_practice_over(points: int) -> void:
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	_practice.show_over(points)


## The revive offer came up: it covers the room, so the running HUD goes.
func _on_revive_offer_shown() -> void:
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	_hint.visible = false


func show_ready() -> void:
	revive_offer.visible = false
	_hint.visible = true
	_pause_button.visible = false
	_back_button.visible = true
	_back_button.tooltip_text = "Rooms" if _practicing else "Home"
	_run_coins.visible = false
	_score.visible = false
	_paused.visible = false
	_game_over.visible = false
	_go_time = -1.0
	if _practicing:
		_practice.show_playing(false)
	if _replaying:
		# The replay taps by itself, and its exit sits in that corner.
		_hint.visible = false
		_back_button.visible = false
		_replay.show_playing()


## `waiting`: a revived bird waits for a tap (the player may have looked away
## for an ad), so "Tap to flap" shows until it comes.
func show_running(waiting: bool = false) -> void:
	revive_offer.visible = false
	_hint.visible = waiting
	_back_button.visible = false
	# A replay has no pause; its exit sits where pause would be.
	_pause_button.visible = not _replaying
	_score.visible = true
	# Practice and replays never pay coins, so no counter.
	_run_coins.visible = not _practicing and not _replaying
	if _practicing:
		_practice.show_playing(false)


## Paused: the score, the sound circles, Resume, and Home (or Back to rooms in
## practice).
func show_paused(value: bool, music_on: bool = true, sfx_on: bool = true) -> void:
	_paused.visible = value
	_pause_button.visible = not value
	_back_button.visible = false
	_score.visible = not value
	_run_coins.visible = not value and not _practicing
	_paused_home.visible = not _practicing
	if value:
		_paused_score.text = _score.text
		(_toggles["music"] as Button).set_pressed_no_signal(music_on)
		(_toggles["sfx"] as Button).set_pressed_no_signal(sfx_on)
		_show_toggle("music")
		_show_toggle("sfx")
	if _practicing:
		_practice.show_playing(value)


## `previous_best` shows as "was 87" on a new best; `rooms` is how many rooms
## this run cleared; `rank` today's place (0 while unknown); `revived_at` the
## score the run was revived at (-1: it wasn't).
func show_game_over(
	score: int,
	best: int,
	is_new_best: bool,
	coins_earned: int,
	previous_best: int = 0,
	rooms: int = 0,
	rank: int = 0,
	seed_value: int = -1,
	revived_at: int = -1
) -> void:
	revive_offer.visible = false
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	_final_value = score
	_best_score.text = best_text(best, is_new_best, previous_best)
	_stat_coins.text = "+%d" % coins_earned
	_stat_rooms.text = str(rooms)
	set_daily_rank(rank)
	_new_best.visible = is_new_best
	_go_caption.visible = not is_new_best
	# A new best moves the score down under the ribbon.
	var top := 130.0 if is_new_best else 122.0
	_final_score.offset_top = top
	_final_score.offset_bottom = top + _final_score.get_combined_minimum_size().y
	_best_score.offset_top = 276.0 if is_new_best else 274.0
	_revived_line.visible = revived_at >= 0
	_revived_text.text = "Revived at %d" % revived_at
	# The heart takes the room text's colour (white on night rooms).
	_revived_icon.modulate = _revived_text.get_theme_color("font_color")
	_revived_line.offset_top = _best_score.offset_top + 26.0
	_revived_line.offset_bottom = (
		_revived_line.offset_top + _revived_line.get_combined_minimum_size().y
	)
	_stats.offset_top = 356.0 if is_new_best else 330.0
	_stats.offset_bottom = _stats.offset_top + _stats.get_combined_minimum_size().y
	_seed.text = seed_text(seed_value)
	_seed.visible = seed_value >= 0
	_seed.offset_top = _stats.offset_bottom + 14.0
	_seed.offset_bottom = _seed.offset_top + _seed.get_combined_minimum_size().y
	_game_over.visible = true
	_new_best.still = reduced_motion
	_go_time = 0.0 if is_new_best and not reduced_motion else FX_TIME
	_step_new_best()


## Today's rank on the game-over stats and dock ("-" until it arrives).
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _stat_rank != null:
		_stat_rank.text = "#%d" % rank if rank > 0 else "-"
	if _dock != null:
		_dock.set_text("rank", "#%d" % rank if rank > 0 else "Ranks")


func _step_new_best() -> void:
	var t := _go_time
	if not _new_best.visible or t >= FX_TIME:
		_final_score.text = str(_final_value)
		_new_best.time = FX_TIME
		_go_time = -1.0
		return
	var k := minf(1.0, t / COUNT_TIME)
	var eased := 1.0 - pow(1.0 - k, 3.0)
	_final_score.text = str(roundi(_final_value * eased))
	_new_best.time = t


func is_new_best_showing() -> bool:
	return _game_over.visible and _new_best.visible


## A short message on the room, e.g. the world's name after switching.
func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(_toast.hide)


## "Seed 123456 · v11": the seed and gameplay version replay the run exactly.
static func seed_text(seed_value: int) -> String:
	return "Seed %d · v%d" % [seed_value, SimConfig.GAMEPLAY_VERSION]


## "Best 92"; on a new best just "was 87" (the ribbon says New best).
static func best_text(best: int, is_new_best: bool, previous_best: int) -> String:
	if is_new_best:
		return "was %d" % previous_best if previous_best > 0 else "Your first best"
	return "Best %d" % best
