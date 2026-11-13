class_name DailyRunScreen
extends Control
## Daily Run (button system A3, a sub-screen): the back arrow and the title at
## the top, today's number and the time to the next map on the room, one paper
## card with the tries (a disc per try: used, next, still free), the best try
## and its place, what the top 10 win and a row to the board, yesterday's
## result under it, and one round main action on the action line: "Try 2"
## starts the next try, "Board" once the day's tries are used, "Retry" while
## offline. The numbers come from a DailyRunInfo; the countdown runs down here
## and asks for a fresh one at the reset.

signal closed
## The main action: start the next try.
signal play_pressed
## "See the board" (and Board once the tries are used).
signal board_pressed
## Watch a run of yesterday's top 3 (its LeaderboardBoard.Entry.run_id).
signal watch_requested(run_id: int)
## Offline Retry, or the countdown reached the reset: ask for today again.
signal refresh_requested

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
const TITLE := "Daily Run"
const SIDE := UiKit.SCREEN_SIDE
const TOP := UiKit.SCREEN_TOP
## Lines on the room under the header, logical px.
const CAPTION_Y := 96.0
const CLOCK_LABEL_Y := 122.0
const CLOCK_Y := 140.0
const CLOCK_SIZE := 40
const CARD_Y := 196.0
const YESTERDAY_GAP := 10.0
const PIP := 46.0
const BEST_SIZE := 18
const LINE_W := 296.0
const OFFLINE := "Connect to the internet to play today's map."
const LOADING := "Loading today's map"

var _info: DailyRunInfo
## Seconds to the reset as the screen counts them down.
var _left_s := -1.0
var _asked_reset := false
var _caption: Label
var _clock_label: Label
var _clock: Label
var _card: PanelContainer
var _pips: HBoxContainer
var _best: Label
var _prizes: Label
var _board: Button
var _yesterday: VBoxContainer
var _yesterday_line: Label
var _watch: Button
var _primary: Button


func _init(info: DailyRunInfo = null) -> void:
	_info = info
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var head := UiKit.header(TITLE, closed.emit)
	add_child(head)
	head.anchor_right = 1.0
	head.offset_left = SIDE
	head.offset_right = -SIDE
	head.offset_top = TOP
	head.offset_bottom = TOP + UiKit.HEADER_HEIGHT
	_caption = UiKit.label("", &"SkyCaption")
	UiKit.across(self, _caption, CAPTION_Y)
	_clock_label = UiKit.label("New map in", &"RoomMuted")
	UiKit.across(self, _clock_label, CLOCK_LABEL_Y)
	_clock = UiKit.label("", &"RoomStat")
	_clock.add_theme_font_size_override("font_size", CLOCK_SIZE)
	UiKit.across(self, _clock, CLOCK_Y)

	_card = PanelContainer.new()
	_card.name = "TriesCard"
	_card.theme_type_variation = &"Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	_card.add_child(col)
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", UiTokens.SPACE_4)
	col.add_child(_pips)
	_best = UiKit.label("", &"NameLabel")
	_best.add_theme_font_size_override("font_size", BEST_SIZE)
	col.add_child(_best)
	_prizes = UiKit.wrapped(prize_line(), &"MutedLabel", LINE_W - 40.0)
	col.add_child(_prizes)
	_board = UiKit.row_button("See the board", UiTokens.PANEL_RAISED)
	_board.name = "Board"
	_board.pressed.connect(board_pressed.emit)
	col.add_child(_board)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE + 8)
	margin.add_theme_constant_override("margin_right", SIDE + 8)
	margin.add_child(_card)
	UiKit.across(self, margin, CARD_Y)

	_yesterday = VBoxContainer.new()
	_yesterday.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_yesterday.add_theme_constant_override("separation", 0)
	_yesterday_line = UiKit.wrapped("", &"RoomMuted", LINE_W)
	_yesterday.add_child(_yesterday_line)
	_watch = UiKit.text_button("", &"PlainButton")
	_watch.name = "Watch"
	_watch.pressed.connect(_on_watch)
	_yesterday.add_child(_watch)
	add_child(_yesterday)
	_yesterday.anchor_right = 1.0

	_primary = UiKit.primary(PLAY_ICON, "Play")
	_primary.name = "Primary"
	_primary.pressed.connect(_on_primary)
	UiKit.place_primary(self, _primary)
	_card.resized.connect(_place_yesterday)
	show_info(_info)


func _process(delta: float) -> void:
	if _left_s < 0.0:
		return
	_left_s = maxf(_left_s - delta, 0.0)
	_clock.text = clock_text(ceili(_left_s))
	if _left_s <= 0.0 and not _asked_reset:
		# A new map: the tries start over.
		_asked_reset = true
		refresh_requested.emit()


## Today's Daily Run arrived (null: still loading).
func show_info(info: DailyRunInfo) -> void:
	_info = info
	if not is_node_ready():
		return
	_asked_reset = false
	var online := info != null and info.is_online()
	_left_s = float(info.resets_in_s) if online and info.resets_in_s >= 0 else -1.0
	_clock_label.visible = online
	_clock.visible = online
	_card.visible = online
	if info == null:
		_caption.text = LOADING
		_primary.visible = false
		_yesterday.visible = false
		return
	_primary.visible = true
	if not online:
		_caption.text = OFFLINE
		_set_primary(RESTART_ICON, "Retry")
		_yesterday.visible = false
		return
	_caption.text = caption_text(info)
	_clock.text = clock_text(info.resets_in_s)
	_fill_pips(info)
	_best.text = best_text(info)
	var next := DailyRunRules.next_try_label(info.tries_used, info.tries_max)
	if next.is_empty():
		_set_primary(TROPHY_ICON, "Board")
	else:
		_set_primary(PLAY_ICON, next)
	_yesterday_line.text = yesterday_text(info.yesterday)
	_yesterday.visible = not _yesterday_line.text.is_empty()
	var leader := _leader()
	_watch.visible = leader != null
	if leader != null:
		_watch.text = "Watch %s's run" % leader.player_name
	_place_yesterday()


func _set_primary(icon: Texture2D, text: String) -> void:
	_primary.icon = icon
	_primary.text = text
	_primary.tooltip_text = text


func _on_primary() -> void:
	if _info == null:
		return
	if not _info.is_online():
		refresh_requested.emit()
	elif _info.tries_left() > 0:
		play_pressed.emit()
	else:
		board_pressed.emit()


func _on_watch() -> void:
	var leader := _leader()
	if leader != null:
		watch_requested.emit(leader.run_id)


## Yesterday's winner, when their replay can be watched.
func _leader() -> LeaderboardBoard.Entry:
	if _info == null or _info.yesterday == null or _info.yesterday.top.is_empty():
		return null
	var first := _info.yesterday.top[0]
	return first if first.run_id > 0 else null


## Yesterday's line sits under the card, whatever its height.
func _place_yesterday() -> void:
	if _yesterday == null or _card == null:
		return
	var top := CARD_Y + _card.size.y + YESTERDAY_GAP
	_yesterday.offset_top = top
	_yesterday.offset_bottom = top + _yesterday.get_combined_minimum_size().y


## A disc per try: used ones in ink with a check, the next one gold with its
## number, the rest an empty ring.
func _fill_pips(info: DailyRunInfo) -> void:
	for c in _pips.get_children():
		_pips.remove_child(c)
		c.queue_free()
	for i in info.tries_max:
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(PIP, PIP)
		var used := i < info.tries_used
		var next := i == info.tries_used
		var fill := UiTokens.INK_LINE if used else (UiTokens.ACTION if next else UiTokens.PANEL)
		var box := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
		if not used and not next:
			box.border_color = UiTokens.EDGE
			box.set_border_width_all(3)
		pip.add_theme_stylebox_override("panel", box)
		if used:
			var tick := TextureRect.new()
			tick.texture = CHECK_ICON
			tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tick.custom_minimum_size = Vector2(22, 22)
			tick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.add_child(tick)
		else:
			var n := UiKit.label(str(i + 1), &"NameLabel")
			n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			pip.add_child(n)
		pip.tooltip_text = "Try %d" % (i + 1)
		_pips.add_child(pip)


## "No. 47 · one map for everyone".
static func caption_text(info: DailyRunInfo) -> String:
	return "No. %d · one map for everyone" % info.number


## 15129 -> "4:12:09".
static func clock_text(seconds: int) -> String:
	var s := maxi(seconds, 0)
	@warning_ignore("integer_division")
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## "Best 31 · #12 of 2,140", or what to do before the first try.
static func best_text(info: DailyRunInfo) -> String:
	if info.best < 0:
		return "%s today" % DailyRunRules.tries_text(info.tries_used, info.tries_max)
	var shown := "Best %d" % info.best
	if info.rank > 0:
		shown += " · #%d of %s" % [info.rank, DailyRunRules.thousands(maxi(info.players, 1))]
	return shown


## "Top 10 win diamonds at the reset: 3, 2, 2, then 1".
static func prize_line() -> String:
	return (
		"Top 10 win diamonds at the reset: %d, %d, %d, then %d"
		% [
			Economy.daily_run_prize(1),
			Economy.daily_run_prize(2),
			Economy.daily_run_prize(3),
			Economy.daily_run_prize(4),
		]
	)


## "Yesterday, No. 46: you were #4 of 1,980." or who won; "" without one.
static func yesterday_text(past: DailyRunInfo.Yesterday) -> String:
	if past == null or past.number <= 0:
		return ""
	var head := "Yesterday, No. %d: " % past.number
	if past.rank > 0:
		var of := DailyRunRules.thousands(maxi(past.players, past.rank))
		return head + "you were #%d of %s." % [past.rank, of]
	if not past.top.is_empty():
		var first := past.top[0]
		return head + "%s won with %d." % [first.player_name, first.score]
	return ""


func primary() -> Button:
	return _primary


func caption() -> String:
	return _caption.text


func best_line() -> String:
	return _best.text


func yesterday_line() -> String:
	return _yesterday_line.text if _yesterday.visible else ""


func watch_button() -> Button:
	return _watch


func board_button() -> Button:
	return _board


func pips() -> HBoxContainer:
	return _pips
