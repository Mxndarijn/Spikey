class_name WinsScreen
extends Control
## The wins boards (docs/DUEL_MODE.md, screens L1 and L2): the leaderboards'
## header with the Scores | Wins switch on Wins, tabs for Battle and Duel (Duel
## until it is built says so), This week | All time, then the players ranked by
## counted wins with their wins and losses and win rate, and the player's own
## row pinned at the bottom. A tap on a row shows that player's record.
## Bot matches never count, so no bot is ever on these boards.

signal closed
signal scores_pressed
## The board to show: mode ("battle", "duel") and period ("week", "all").
signal board_requested(mode: String, period: String)
signal record_requested(mode: String, period: String, who: String)

const SIDE := UiKit.SCREEN_SIDE
const BOTTOM := 40
const ROW_H := 40.0
const MODES: Array[String] = ["battle", "duel"]
const MODE_NAMES: Array[String] = ["Battle", "Duel"]
const PERIODS: Array[String] = ["week", "all"]
const PERIOD_NAMES: Array[String] = ["This week", "All time"]
const LOADING := "Loading the board"
const EMPTY := "No counted wins yet. Win a battle to be the first."
const DUEL_SOON := "Duel is coming soon. Its wins will show here."

var mode := "battle"
var period := "week"
var _caption: Label
var _list: VBoxContainer
var _pinned: Label
var _tabs: Array[Button] = []
var _periods: Array[Button] = []
var _board := {}
var _record: Control


func _init(p_mode: String = "battle", p_period: String = "week") -> void:
	mode = p_mode if p_mode in MODES else "battle"
	period = p_period if p_period in PERIODS else "week"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiKit.SCREEN_TOP)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	margin.add_child(col)
	var switch := BoardSwitch.new(BoardSwitch.WINS)
	switch.picked.connect(func(_i: int) -> void: scores_pressed.emit())
	col.add_child(UiKit.header("Leaderboards", closed.emit, switch))
	col.add_child(_strip(MODE_NAMES, _tabs, _pick_mode))
	col.add_child(_strip(PERIOD_NAMES, _periods, _pick_period))
	_caption = UiKit.label(LOADING, &"RoomMuted")
	_caption.add_theme_font_size_override("font_size", 13)
	col.add_child(_caption)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", UiTokens.SPACE_1)
	scroll.add_child(_list)
	_pinned = UiKit.label("", &"SmallNameLabel")
	_pinned.name = "Pinned"
	var gold := UiTheme.flat(UiTokens.ACTION, UiTokens.RADIUS_PILL, 0)
	gold.content_margin_left = UiTokens.SPACE_4
	gold.content_margin_right = UiTokens.SPACE_4
	gold.content_margin_top = UiTokens.SPACE_2
	gold.content_margin_bottom = UiTokens.SPACE_2
	_pinned.add_theme_stylebox_override("normal", gold)
	_pinned.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pinned.visible = false
	col.add_child(_pinned)
	_select()


func _strip(names: Array[String], into: Array[Button], pick: Callable) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)
	var group := ButtonGroup.new()
	for i in names.size():
		var tab := Button.new()
		tab.name = names[i].replace(" ", "")
		tab.theme_type_variation = &"TabButton"
		tab.text = names[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(pick.bind(i))
		into.append(tab)
		row.add_child(tab)
	return bar


func _pick_mode(i: int) -> void:
	mode = MODES[i]
	_select()


func _pick_period(i: int) -> void:
	period = PERIODS[i]
	_select()


## Shows the chosen tabs, loading, and asks for the board.
func _select() -> void:
	_tabs[MODES.find(mode)].button_pressed = true
	_periods[PERIODS.find(period)].button_pressed = true
	_clear()
	_pinned.visible = false
	if mode == "duel":
		_caption.text = DUEL_SOON
		return
	_caption.text = LOADING
	board_requested.emit(mode, period)


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


## A board arrived (get_wins_board's answer).
func show_board(p_mode: String, p_period: String, board: Dictionary) -> void:
	if p_mode != mode or p_period != period or _list == null:
		return
	_board = board
	_clear()
	var entries: Array = board.get("entries", []) if board.get("entries") is Array else []
	var players := int(board.get("players", 0))
	var resets := int(board.get("resets_in_s", -1))
	var parts: Array[String] = [LeaderboardScreen.count(players, "player")]
	if resets > 0:
		parts.insert(0, "Resets in %s" % LeaderboardScreen.duration(resets))
	_caption.text = EMPTY if entries.is_empty() else " · ".join(parts)
	for e: Variant in entries:
		if e is Dictionary:
			_list.add_child(_row(e as Dictionary))
	var me: Variant = board.get("me")
	if me is Dictionary:
		var m := me as Dictionary
		var rank := "#%d" % int(m.get("rank")) if m.get("rank") != null else "Not ranked yet"
		_pinned.text = "%s  You  %s" % [rank, record_line(m)]
		_pinned.visible = true


static func record_line(e: Dictionary) -> String:
	var line := "%d–%d" % [int(e.get("wins", 0)), int(e.get("losses", 0))]
	if e.get("rate") != null:
		line += " · %d%%" % int(e.get("rate"))
	return line


func _row(e: Dictionary) -> Button:
	var b := UiKit.row_button("", UiTokens.PANEL)
	b.name = "Row%d" % _list.get_child_count()
	b.icon = null
	b.custom_minimum_size = Vector2(0, ROW_H)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = UiTokens.SPACE_4
	line.offset_right = -UiTokens.SPACE_4
	line.add_theme_constant_override("separation", UiTokens.SPACE_2)
	b.add_child(line)
	var rank := UiKit.label(str(int(e.get("rank", 0))), &"MutedLabel", false)
	rank.custom_minimum_size = Vector2(26, 0)
	line.add_child(rank)
	var who := str(e.get("name", "")) + (" (you)" if bool(e.get("is_me", false)) else "")
	var label := UiKit.label(who, &"SmallNameLabel", false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	var rec := UiKit.label(record_line(e), &"MutedLabel", false)
	rec.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	line.add_child(rec)
	var wins := UiKit.label(str(int(e.get("wins", 0))), &"NameLabel", false)
	wins.name = "Wins"
	wins.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	wins.custom_minimum_size = Vector2(26, 0)
	wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(wins)
	var id := str(e.get("who", ""))
	b.pressed.connect(func() -> void: record_requested.emit(mode, period, id))
	return b


## A player's record over the board (get_match_record's answer).
func show_record(record: Dictionary) -> Control:
	if _record != null:
		_record.queue_free()
	var parts := BattleKit.card_over_scrim(close_record)
	_record = parts[0]
	_record.name = "Record"
	var col: VBoxContainer = parts[1]
	var title := UiKit.label(str(record.get("name", "")), &"NameLabel", false)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(60, 0)
	col.add_child(UiKit.card_head(title, close_record))
	var sub := UiKit.label(
		"%s · %s" % [MODE_NAMES[MODES.find(mode)], PERIOD_NAMES[PERIODS.find(period)]],
		&"MutedLabel",
		false
	)
	col.add_child(sub)
	var rate := "%d%%" % int(record.get("rate")) if record.get("rate") != null else "–"
	var facts := [
		["Counted wins", str(int(record.get("wins", 0)))],
		["Win rate", rate],
		["Lost · draws", "%d · %d" % [int(record.get("losses", 0)), int(record.get("draws", 0))]],
		["Best streak", str(int(record.get("best_streak", 0)))],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTokens.SPACE_4)
	for f: Array in facts:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var k := UiKit.label(str(f[0]).to_upper(), &"MutedLabel", false)
		k.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
		cell.add_child(k)
		var v := UiKit.label(str(f[1]), &"NameLabel", false)
		v.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
		cell.add_child(v)
		grid.add_child(cell)
	col.add_child(grid)
	var last: Array = record.get("last", []) if record.get("last") is Array else []
	if not last.is_empty():
		var head := UiKit.label("LAST MATCHES", &"MutedLabel", false)
		head.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
		col.add_child(head)
	for m: Variant in last:
		if m is Dictionary:
			var l := UiKit.wrapped(match_line(m as Dictionary), &"InkLabel", 260)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL)
			col.add_child(l)
	add_child(_record)
	return _record


## "Won 6–3 vs Jun · random", "Lost 4–6 vs Ada · friend · not counted".
static func match_line(m: Dictionary) -> String:
	var result := str(m.get("result", "")).capitalize()
	var line := (
		"%s %s vs %s · %s"
		% [
			result,
			str(m.get("score", "")).replace("-", "–"),
			str(m.get("opponent", "")),
			str(m.get("how", ""))
		]
	)
	if not bool(m.get("counted", true)):
		line += " · not counted"
	return line


func close_record() -> void:
	if _record != null:
		_record.queue_free()
		_record = null


func record() -> Control:
	return _record


func rows() -> Array[Button]:
	var out: Array[Button] = []
	for c in _list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c as Button)
	return out


func caption_text() -> String:
	return _caption.text


func pinned_text() -> String:
	return _pinned.text if _pinned.visible else ""
