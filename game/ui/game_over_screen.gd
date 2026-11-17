class_name GameOverScreen
extends Control
## Game over on the emptied room (GameOverStage clears the hazards and floats the flyer, big and
## dazed, to FLYER_Y): "Game over", the score, "Best 92", "Revived at 63" when the run used its
## revive, a stats row (+coins, rooms cleared this run, today's rank), the run's seed, Home in the
## corner slot and the Game over dock, the same slots as Home's (Rooms, Style | Again | Ranks,
## Runs). A new best gets the gold ribbon, the score counting up, three sparkles and confetti that
## falls through once (still with reduced motion).
## A run that reaches best-score milestones (show_prize) gets a cream pill in the seed's place:
## "+6 for Best 150 and 200 · Yours once checked" (the server pays them after its check;
## the seed is still in Your runs). A Daily Run try keeps its tries line there instead.
## A Daily Run try (show_daily) says "Daily Run" instead of "Game over", its
## place on the Daily Run board in the stats, the day's number, the tries left
## and the time to the next map where the seed goes, and its dock has Share where Rooms is and
## the next try ("Try 3", or "Board" after the last) as its main action.

## A dock item or the corner was tapped: "home" (the corner), "rooms",
## "style", "again", "rank", "runs" or (a Daily Run) "share".
signal dock_pressed(id: String)

const COIN_ICON := preload("res://assets/ui/coin.svg")
const HOME_ICON := preload("res://assets/ui/icons/home.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const RUNS_ICON := preload("res://assets/ui/icons/history.svg")
const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
const SHARE_ICON := preload("res://assets/ui/icons/share.svg")
const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const CAPTION := "Game over"
## After the prize pill's diamonds: the server pays once it has checked the run.
const PRIZE_AFTER := "Yours once checked"
## A new best counts the score up over COUNT_TIME; the effect runs FX_TIME.
const COUNT_TIME := 1.1
const FX_TIME := 2.6
## The stats row: column width, gap, and the number's size (it shrinks to
## STAT_MIN to fit "+1240").
const STAT_W := 80.0
const STAT_GAP := 6
## The stats row stays inside 54..306 px, clear of a crashed flyer lying on
## either wall (it can come to rest at any height).
const WALL_CLEAR := 54.0
const STAT_SIZE := 26
const STAT_MIN := 12
const STAT_ICON := 26.0
## Top of each line, logical px. Game over (normal / new best): the caption,
## the score, Best (Revived at sits REVIVED_GAP under it), the flyer's centre
## (GameOverStage.SPOT) and the stats row, with the seed SEED_GAP under it and
## the dock below. Nothing on it overlaps the flyer: Best and Revived at end
## above it, the stats start below it.
const CAPTION_Y := 60.0
const CAPTION_SIZE := 24
const SCORE_Y := 78.0
const SCORE_Y_NEW_BEST := 106.0
const BEST_Y := 228.0
const BEST_Y_NEW_BEST := 252.0
const BEST_SIZE := 18
const REVIVED_GAP := 26.0
const FLYER_Y := 334.0
const STATS_Y := 366.0
const SEED_GAP := 2.0
## The stats card behind the stats and the seed: its side inset and padding.
const STATS_CARD_SIDE := 40.0
const STATS_CARD_PAD := 6.0
## Extra room under the seed line inside the card.
const STATS_CARD_PAD_BOTTOM := 10.0
## Every stat's value line has this height.
const STAT_LINE_H := 32.0
## The final score shrinks to fit the screen from this many digits.
const FINAL_SCORE_W := UiTokens.SIZE_VIEWPORT_W - 48.0
const FINAL_SCORE_MIN := 64

var _caption := Label.new()
var _final_score := Label.new()
var _best_score := Label.new()
var _stats := HBoxContainer.new()
## The run's seed in small text, so a player can report a run that looked wrong.
var _seed := Label.new()
## "Revived at 63" under the best score, when the run used its revive.
var _revived_line := HBoxContainer.new()
var _revived_icon := TextureRect.new()
var _revived_text := Label.new()
## The milestones this run reached (show_prize), in the seed's place.
var _prize := CenterContainer.new()
var _prize_text := Label.new()
var _stat_coins: Label
var _stat_rooms: Label
var _stat_rank: Label
var _dock: Dock
## Game over of a Daily Run try: Share where Rooms is, the next try in the middle.
var _daily_dock: Dock
var _daily := false
var _stat_rank_word: Label
var _home: Button
var _new_best := NewBestFx.new()
var _final_value := 0
## Seconds into the new-best effect (-1: not running).
var _time := -1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_new_best)
	_caption.theme_type_variation = &"SkyLabel"
	_caption.text = CAPTION
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("font", GameFonts.display())
	_caption.add_theme_font_size_override("font_size", CAPTION_SIZE)
	UiKit.across(self, _caption, CAPTION_Y)
	_final_score.theme_type_variation = &"RoomBigScore"
	_final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_final_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _final_score, SCORE_Y)
	_best_score.theme_type_variation = &"SkyCaption"
	_best_score.add_theme_font_size_override("font_size", BEST_SIZE)
	_best_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _best_score, BEST_Y)
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
	UiKit.across(self, _revived_line, BEST_Y + REVIVED_GAP)
	_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.add_theme_constant_override("separation", STAT_GAP)
	_stat_coins = _stat(_stats, "Coins", COIN_ICON)
	_stat_rooms = _stat(_stats, "Rooms")
	_stat_rank = _stat(_stats, "Today")
	_stat_rank_word = _stat_rank.get_parent().get_parent().get_child(1) as Label
	UiKit.across(self, _stats, STATS_Y)
	_seed.theme_type_variation = &"RoomMuted"
	_seed.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _seed, STATS_Y + 56.0)
	_prize.name = "Prize"
	_prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 2)
	box.content_margin_left = 8
	box.content_margin_right = 12
	pill.add_theme_stylebox_override("panel", box)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var icon := TextureRect.new()
	icon.texture = DIAMOND_ICON
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_prize_text.theme_type_variation = &"CaptionLabel"
	_prize_text.add_theme_color_override("font_color", UiTokens.ON_PANEL)
	row.add_child(_prize_text)
	pill.add_child(row)
	_prize.add_child(pill)
	_prize.visible = false
	UiKit.across(self, _prize, STATS_Y + 56.0)
	# Home leaves from the corner slot, like every back arrow.
	_home = UiKit.disc_button(HOME_ICON, "Home", UiKit.Disc.PAPER, UiKit.ICON_BUTTON)
	_home.name = "Home"
	_home.custom_minimum_size = Vector2(UiKit.ICON_BUTTON, UiKit.ICON_BUTTON)
	# A solid disc, as Home's Settings: a bare glyph read as decoration.
	for state in ["normal", "hover", "disabled"]:
		_home.add_theme_stylebox_override(state, UiTheme.solid(UiTokens.PANEL))
	for state in ["pressed", "hover_pressed"]:
		_home.add_theme_stylebox_override(state, UiTheme.solid(UiTokens.PANEL_RAISED))
	_home.pressed.connect(dock_pressed.emit.bind("home"))
	UiKit.place_corner(self, _home)
	_dock = (
		Dock
		. new(
			[
				{"id": "rooms", "icon": ROOMS_ICON, "text": "Rooms"},
				{"id": "style", "icon": STYLE_ICON, "text": "Style"},
			],
			[
				{"id": "rank", "icon": TROPHY_ICON, "text": "Ranks", "tip": "Leaderboards"},
				{"id": "runs", "icon": RUNS_ICON, "text": "Runs", "tip": "Your runs"},
			],
			{"id": "again", "icon": RESTART_ICON, "text": "Again"}
		)
	)
	_dock.pressed.connect(dock_pressed.emit)
	add_child(_dock)
	_daily_dock = (
		Dock
		. new(
			[
				{"id": "share", "icon": SHARE_ICON, "text": "Share", "tip": "Share your try"},
				{"id": "style", "icon": STYLE_ICON, "text": "Style"},
			],
			[
				{"id": "rank", "icon": TROPHY_ICON, "text": "Ranks", "tip": "Leaderboards"},
				{"id": "runs", "icon": RUNS_ICON, "text": "Runs", "tip": "Your runs"},
			],
			{"id": "again", "icon": RESTART_ICON, "text": "Again"}
		)
	)
	_daily_dock.pressed.connect(dock_pressed.emit)
	add_child(_daily_dock)
	_set_daily(false)


func _process(delta: float) -> void:
	if _time >= 0.0 and visible and _new_best.visible:
		_time += delta
		_step_new_best()


## Shows the run's result. `previous_best` shows as "was 87" on a new best;
## `rooms` is how many rooms this run cleared; `rank` today's place (0 while
## unknown); `seed_line` the seed (seed_text; "" hides it); `revived_at` the score the run
## was revived at (-1: it wasn't). `still`: reduced motion (no count-up).
func show_result(
	score: int,
	best: int,
	is_new_best: bool,
	coins_earned: int,
	previous_best: int,
	rooms: int,
	rank: int,
	seed_line: String,
	revived_at: int,
	still: bool
) -> void:
	_set_daily(false)
	_final_value = score
	_final_score.add_theme_font_size_override("font_size", final_score_size(score))
	_best_score.text = best_text(best, is_new_best, previous_best)
	_stat_coins.text = "+%d" % coins_earned
	_fit_stat(_stat_coins, STAT_W - STAT_ICON)
	_stat_rooms.text = str(rooms)
	_fit_stat(_stat_rooms, STAT_W)
	set_daily_rank(rank)
	_new_best.visible = is_new_best
	_caption.visible = not is_new_best
	# A new best moves the score down under the ribbon.
	var top := SCORE_Y_NEW_BEST if is_new_best else SCORE_Y
	_final_score.offset_top = top
	_final_score.offset_bottom = top + _final_score.get_combined_minimum_size().y
	_best_score.offset_top = BEST_Y_NEW_BEST if is_new_best else BEST_Y
	_revived_line.visible = revived_at >= 0
	_revived_text.text = "Revived at %d" % revived_at
	# The heart takes the room text's colour (white on night rooms).
	_revived_icon.modulate = _revived_text.get_theme_color("font_color")
	_revived_line.offset_top = _best_score.offset_top + REVIVED_GAP
	_revived_line.offset_bottom = (
		_revived_line.offset_top + _revived_line.get_combined_minimum_size().y
	)
	_stats.offset_top = STATS_Y
	_stats.offset_bottom = _stats.offset_top + _stats.get_combined_minimum_size().y
	_seed.text = seed_line
	_seed.visible = not seed_line.is_empty()
	_seed.offset_top = _stats.offset_bottom + SEED_GAP
	_seed.offset_bottom = _seed.offset_top + _seed.get_combined_minimum_size().y
	_prize.visible = false
	visible = true
	# The corner disc keeps its 48 px (it grew while the screen was hidden).
	_home.size = _home.custom_minimum_size
	queue_redraw()
	_new_best.still = still
	_time = 0.0 if is_new_best and not still else FX_TIME
	_step_new_best()


## Turns the result just shown into a Daily Run try's: `number` the day's
## Daily Run, `tries_line` ("1 try left · new map in 4h 12m") in place of the
## seed, `next` the main action's label ("Try 3", "Board").
func show_daily(number: int, tries_line: String, next: String) -> void:
	queue_redraw()
	_set_daily(true)
	_caption.text = "Daily Run"
	_seed.text = "No. %d · %s" % [number, tries_line]
	_seed.visible = not tries_line.is_empty()
	_seed.offset_bottom = _seed.offset_top + _seed.get_combined_minimum_size().y
	# The tries line matters more on a Daily Run: no prize pill there.
	_prize.visible = false
	_daily_dock.set_text("again", next)
	_show_rank(0)


func _set_daily(on: bool) -> void:
	_daily = on
	_caption.text = CAPTION
	_stat_rank_word.text = "Daily Run" if on else "Today"
	_dock.visible = not on
	_daily_dock.visible = on


func is_daily() -> bool:
	return _daily


## The dock in use (the Daily Run one after show_daily).
func dock() -> Dock:
	return _daily_dock if _daily else _dock


func caption_text() -> String:
	return _caption.text


func seed_line() -> String:
	return _seed.text if _seed.visible else ""


## After show_result: the milestones this run reached that weren't won yet
## (EarnRules.new_prizes). Shows the pill in the seed's place; none: nothing.
func show_prize(scores: Array[int]) -> void:
	queue_redraw()
	if scores.is_empty() or _daily:
		_prize.visible = false
		return
	_prize_text.text = prize_text(scores)
	_seed.visible = false
	_prize.visible = true
	_prize.offset_top = _stats.offset_bottom + SEED_GAP
	_prize.offset_bottom = _prize.offset_top + _prize.get_combined_minimum_size().y


func prize_line() -> String:
	return _prize_text.text if _prize.visible else ""


## The pill's rect on screen, for tests.
func prize_rect() -> Rect2:
	var min_size := _prize.get_combined_minimum_size()
	var pill := _prize.get_child(0) as Control
	var w := pill.get_combined_minimum_size().x
	return Rect2((UiTokens.SIZE_VIEWPORT_W - w) / 2.0, _prize.offset_top, w, min_size.y)


## "+3 for Best 150 · Yours once checked"; two: "+6 for Best 150
## and 200 · ..."; more: "+9 for Best 150 to 250 · ...".
static func prize_text(scores: Array[int]) -> String:
	var total := EarnRules.prizes_total(scores)
	var which := UiKit.thousands(scores[0])
	if scores.size() == 2:
		which += " and " + UiKit.thousands(scores[1])
	elif scores.size() > 2:
		which += " to " + UiKit.thousands(scores[-1])
	return "+%d for Best %s · %s" % [total, which, PRIZE_AFTER]


## Hidden, with the effect stopped.
func hide_result() -> void:
	visible = false
	_time = -1.0


## Today's rank on the stats ("-" until it arrives); on a Daily Run try, its
## place on the Daily Run board.
func set_daily_rank(rank: int) -> void:
	if not _daily:
		_show_rank(rank)


## A Daily Run try's place on the Daily Run board ("-" until it arrives).
func set_daily_run_rank(rank: int) -> void:
	if _daily:
		_show_rank(rank)


func _show_rank(rank: int) -> void:
	_stat_rank.text = "#%d" % rank if rank > 0 else "-"
	_fit_stat(_stat_rank, STAT_W)


## The corner's Home button.
func home_button() -> Button:
	return _home


func is_new_best_showing() -> bool:
	return visible and _new_best.visible


func score_text() -> String:
	return _final_score.text


## The final score's font size: big, smaller for a long score so it never
## runs past the screen edges.
static func final_score_size(score: int) -> int:
	return UiKit.fit_font_size(
		str(score), GameFonts.display(), UiTheme.BIG_SCORE_SIZE, FINAL_SCORE_W, FINAL_SCORE_MIN
	)


## "Seed ES8SS-62G0N · v21", "Seed RS8SS-62H0N · Halloween · v21": the code
## (SeedCode) holds the seed, season and version, so it replays the run exactly.
static func seed_text(
	seed_value: int, season: int = Seasons.NONE, version: int = SimConfig.GAMEPLAY_VERSION
) -> String:
	var shown := "Seed " + SeedCode.encode(seed_value, season, version)
	if season != Seasons.NONE:
		shown += " · " + SeasonCalendar.display_name(season)
	return shown + " · v%d" % version


## "Best 92"; on a new best just "was 87" (the ribbon says New best).
static func best_text(best: int, is_new_best: bool, previous_best: int) -> String:
	if is_new_best:
		return "was %d" % previous_best if previous_best > 0 else "Your first best"
	return "Best %d" % best


func _step_new_best() -> void:
	var t := _time
	if not _new_best.visible or t >= FX_TIME:
		_final_score.text = str(_final_value)
		_new_best.time = FX_TIME
		_time = -1.0
		return
	var k := minf(1.0, t / COUNT_TIME)
	var eased := 1.0 - pow(1.0 - k, 3.0)
	_final_score.text = str(roundi(_final_value * eased))
	_new_best.time = t


## One stat: a big number (with an icon) over a small word.
static func _stat(row: HBoxContainer, word: String, icon: Texture2D = null) -> Label:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(STAT_W, 0)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	# One height for every value line, so the names under them share a
	# baseline even when a long rank shrinks its number.
	line.custom_minimum_size.y = STAT_LINE_H
	if icon != null:
		var pic := TextureRect.new()
		pic.texture = icon
		pic.custom_minimum_size = Vector2(20, 20)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(pic)
	# On the stats card (paper), so ink in every world.
	var value := UiKit.label("", &"RoomStat")
	value.add_theme_color_override("font_color", UiTokens.ON_PANEL)
	line.add_child(value)
	col.add_child(line)
	var name_label := UiKit.label(word, &"RoomMuted")
	name_label.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	col.add_child(name_label)
	row.add_child(col)
	return value


## The stats card: one solid paper surface behind the stats row and the seed
## (or prize) line, so they read on every world, busy night skylines too.
func _draw() -> void:
	if _stats == null or not _stats.is_inside_tree():
		return
	var bottom := _stats.offset_bottom
	for line: Control in [_seed, _prize]:
		if line.visible:
			bottom = maxf(bottom, line.offset_top + line.get_combined_minimum_size().y)
	var rect := Rect2(
		STATS_CARD_SIDE,
		_stats.offset_top - STATS_CARD_PAD,
		size.x - STATS_CARD_SIDE * 2,
		bottom - _stats.offset_top + STATS_CARD_PAD + STATS_CARD_PAD_BOTTOM
	)
	draw_style_box(UiTheme.solid(UiTokens.PANEL, UiTokens.RADIUS_M, 0), rect)


## A stat's number shrinks to stay inside its column ("+1240", "#1234").
static func _fit_stat(value: Label, room: float) -> void:
	var font := value.get_theme_font("font") if value.is_inside_tree() else GameFonts.display()
	var size := UiKit.fit_font_size(value.text, font, STAT_SIZE, room, STAT_MIN)
	value.add_theme_font_size_override("font_size", size)
