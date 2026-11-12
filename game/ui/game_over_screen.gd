class_name GameOverScreen
extends Control
## Game over on the room: "Game over", the score, "Best 92", "Revived at 63"
## when the run used its revive, a stats row (+coins, rooms cleared this run,
## today's rank), the run's seed, and the Game over dock (Home, Rooms | Again
## | #rank, Style). A new best gets the gold ribbon, the score counting up,
## three sparkles and confetti that falls through once (still with reduced
## motion).

## A dock item was tapped: "home", "rooms", "again", "rank" or "style".
signal dock_pressed(id: String)

const COIN_ICON := preload("res://assets/ui/coin.svg")
const HOME_ICON := preload("res://assets/ui/icons/home.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
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
var _stat_coins: Label
var _stat_rooms: Label
var _stat_rank: Label
var _dock: Dock
var _new_best := NewBestFx.new()
var _final_value := 0
## Seconds into the new-best effect (-1: not running).
var _time := -1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_new_best)
	_caption.theme_type_variation = &"SkyLabel"
	_caption.text = "Game over"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _caption, 104)
	_final_score.theme_type_variation = &"RoomBigScore"
	_final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_final_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _final_score, 122)
	_best_score.theme_type_variation = &"SkyCaption"
	_best_score.add_theme_font_size_override("font_size", 16)
	_best_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _best_score, 274)
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
	UiKit.across(self, _revived_line, 300)
	_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.add_theme_constant_override("separation", STAT_GAP)
	_stat_coins = _stat(_stats, "coins", COIN_ICON)
	_stat_rooms = _stat(_stats, "rooms")
	_stat_rank = _stat(_stats, "today")
	UiKit.across(self, _stats, 330)
	_seed.theme_type_variation = &"RoomMuted"
	_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _seed, 400)
	_dock = (
		Dock
		. new(
			[
				{"id": "home", "icon": HOME_ICON, "text": "Home", "back": true},
				{"id": "rooms", "icon": ROOMS_ICON, "text": "Rooms"},
			],
			[
				{"id": "rank", "icon": TROPHY_ICON, "text": "Ranks", "tip": "Leaderboards"},
				{"id": "style", "icon": STYLE_ICON, "text": "Style"},
			],
			{"id": "again", "icon": RESTART_ICON, "text": "Again"}
		)
	)
	_dock.pressed.connect(dock_pressed.emit)
	add_child(_dock)


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
	_seed.text = seed_line
	_seed.visible = not seed_line.is_empty()
	_seed.offset_top = _stats.offset_bottom + 14.0
	_seed.offset_bottom = _seed.offset_top + _seed.get_combined_minimum_size().y
	visible = true
	_new_best.still = still
	_time = 0.0 if is_new_best and not still else FX_TIME
	_step_new_best()


## Hidden, with the effect stopped.
func hide_result() -> void:
	visible = false
	_time = -1.0


## Today's rank on the stats and the dock ("-" until it arrives).
func set_daily_rank(rank: int) -> void:
	_stat_rank.text = "#%d" % rank if rank > 0 else "-"
	_fit_stat(_stat_rank, STAT_W)
	_dock.set_text("rank", "#%d" % rank if rank > 0 else "Ranks")


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


## A stat's number shrinks to stay inside its column ("+1240", "#1234").
static func _fit_stat(value: Label, room: float) -> void:
	var font := value.get_theme_font("font") if value.is_inside_tree() else GameFonts.display()
	var size := UiKit.fit_font_size(value.text, font, STAT_SIZE, room, STAT_MIN)
	value.add_theme_font_size_override("font_size", size)
