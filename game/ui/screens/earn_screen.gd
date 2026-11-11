class_name EarnScreen
extends Control
## Earn diamonds (minimal kit): every way to win diamonds, each a paper card
## that says what is next. Opens from the wallet (Home, Your look, Customize
## lists) and from the prize popup's link.
## - Daily board: the three prize tiers (Economy.DAILY_PRIZES), the player's
##   place today and the time to the reset (from the Daily LeaderboardBoard).
## - Best score: the four milestones (EarnRules), won or still to win, and a bar.
## - Streak: this week of days in a row as seven dots.
## Ends with a button to the Shop. Main hands it the player's EarnStatus
## (show_status) and the Daily board (show_board) as they arrive; offline it
## shows the last numbers it had under an "Offline" banner.

signal closed
## "Buy diamonds in the Shop".
signal store_pressed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const SHOP_ICON := preload("res://assets/ui/icons/shop.svg")
const TITLE := "Diamonds"
const SIDE := 14
const TOP := 36
const BOTTOM := 24
const OFFLINE := "Offline. Showing what you had last time."
const SHOP := "Buy diamonds in the Shop"
## Room for a sentence inside a card (or the banner) on a 360 px screen.
const LINE_W := 300.0
const TIERS: Array[String] = ["#1", "#2 and #3", "#4 to #10"]

var _profile: Profile
var _status: EarnStatus
var _board: LeaderboardBoard
var _balance := CoinPill.new(DIAMOND_ICON)
var _banner: PanelContainer
var _reset: Label
var _tiers: Array[PanelContainer] = []
var _daily_line: Label
var _miles: Array[PanelContainer] = []
var _mile_labels: Array[Label] = []
var _bar: ProgressLine
var _best_line: Label
var _dots: Array[PanelContainer] = []
var _streak_line: Label
var _shop: Button


func _init(profile: Profile) -> void:
	_profile = profile
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", TOP)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	_balance.set_amount(_profile.diamonds)
	var header := UiKit.header(TITLE, closed.emit, _balance)
	(header.get_node("Title") as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(header)
	col.add_child(_offline_banner())
	col.add_child(_daily_card())
	col.add_child(_best_card())
	col.add_child(_streak_card())
	col.add_child(UiKit.spacer(0, true))
	col.add_child(_shop_button())
	_refresh()


## The player's progress arrived (or the last known one, offline).
func show_status(status: EarnStatus) -> void:
	_status = status
	_balance.set_amount(_profile.diamonds)
	if is_node_ready():
		_refresh()


## A board arrived; only the Daily one is used.
func show_board(board: LeaderboardBoard) -> void:
	if board == null or board.id != LeaderboardService.DAILY:
		return
	_board = board
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	var status := shown_status()
	_banner.visible = is_offline()
	_reset.text = reset_text(_board)
	var tier := tier_index(_board)
	for i in _tiers.size():
		_chip_style(_tiers[i], UiTokens.ACTION if i == tier else UiTokens.PANEL_RAISED)
	_daily_line.text = daily_line(_board)
	var next := EarnRules.next_milestone(status.milestones)
	var scores := EarnRules.milestone_scores()
	for i in scores.size():
		var won := status.milestones.has(scores[i])
		var fill := UiTokens.PANEL_RAISED
		if won:
			fill = UiTokens.INK_LINE
		elif scores[i] == next:
			fill = UiTokens.ACTION
		_chip_style(_miles[i], fill)
		var text_color := UiTokens.ON_PRIMARY if won else UiTokens.ON_PANEL
		for l: Label in _miles[i].find_children("*", "Label", true, false):
			l.add_theme_color_override("font_color", text_color)
		_mile_labels[i].text = milestone_label(status, scores[i])
	_bar.ratio = EarnRules.progress(status.best)
	_best_line.text = best_line(status)
	var filled := EarnRules.week_days(maxi(status.streak, 0))
	for i in _dots.size():
		var on := i < filled
		_chip_style(_dots[i], UiTokens.INK_LINE if on else UiTokens.EDGE, UiTokens.RADIUS_PILL)
		var l := _dots[i].get_child(0) as Label
		l.add_theme_color_override("font_color", UiTokens.ON_PRIMARY if on else UiTokens.ON_PANEL)
	_streak_line.text = streak_line(status)


## What the cards show: the status main handed over, else a guess from the
## save until it arrives.
func shown_status() -> EarnStatus:
	if _status != null:
		return _status
	return EarnStatus.from_profile(_profile)


## The server could not be asked: the cards show old or guessed numbers.
func is_offline() -> bool:
	return _status != null and not _status.known


func _offline_banner() -> PanelContainer:
	_banner = PanelContainer.new()
	_banner.name = "Offline"
	var box := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, UiTokens.SPACE_2)
	box.content_margin_left = 14
	box.content_margin_right = 14
	_banner.add_theme_stylebox_override("panel", box)
	_banner.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	var l := UiKit.wrapped(OFFLINE, &"OnInkLabel", LINE_W)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_child(l)
	return _banner


## A paper card: its title at the left, `right` at the right, then `body`.
func _card(title: String, right: Control, body: Array[Control]) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = title.replace(" ", "")
	card.theme_type_variation = &"Card"
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, UiTokens.SPACE_3)
	box.content_margin_left = 14
	box.content_margin_right = 14
	card.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	card.add_child(col)
	var top := HBoxContainer.new()
	var name_label := UiKit.label(title, &"InkLabel", false)
	name_label.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(right)
	col.add_child(top)
	for c in body:
		col.add_child(c)
	return card


func _daily_card() -> PanelContainer:
	_reset = UiKit.label("", &"MutedLabel", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	for i in TIERS.size():
		var chip := _chip(TIERS[i], _diamonds_row(_tier_prize(i)))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(chip)
		_tiers.append(chip)
	_daily_line = UiKit.wrapped("", &"MutedLabel", LINE_W)
	_daily_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return _card("Daily board", _reset, [row, _daily_line])


func _best_card() -> PanelContainer:
	var grid := GridContainer.new()
	grid.columns = EarnRules.MILESTONES.size()
	grid.add_theme_constant_override("h_separation", 6)
	for score in EarnRules.milestone_scores():
		var label := UiKit.label("", &"CaptionLabel")
		var chip := _chip(str(score), label, true)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(chip)
		_miles.append(chip)
		_mile_labels.append(label)
	_bar = ProgressLine.new()
	_best_line = UiKit.wrapped("", &"MutedLabel", LINE_W)
	_best_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return _card("Best score", UiKit.label("Once each", &"MutedLabel"), [grid, _bar, _best_line])


func _streak_card() -> PanelContainer:
	var right := _diamonds_row(EarnRules.STREAK_PRIZE)
	var every := UiKit.label("every %d days" % EarnRules.STREAK_DAYS, &"CaptionLabel")
	right.add_child(every)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in EarnRules.STREAK_DAYS:
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(0, 30)
		dot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := UiKit.label(str(i + 1), &"StatusLabel")
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_child(l)
		row.add_child(dot)
		_dots.append(dot)
	_streak_line = UiKit.wrapped("", &"MutedLabel", LINE_W)
	_streak_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return _card("Streak", right, [row, _streak_line])


## A small tile on a card: `top` over `below`. `big`: the top in display type.
func _chip(top: String, below: Control, big: bool = false) -> PanelContainer:
	var chip := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(col)
	var l := UiKit.label(top, &"CaptionLabel")
	if big:
		l.add_theme_font_override("font", GameFonts.display())
		l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	col.add_child(l)
	below.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(below)
	_chip_style(chip, UiTokens.PANEL_RAISED)
	return chip


## A diamond and a number ("◆ 3").
func _diamonds_row(count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var icon := TextureRect.new()
	icon.texture = DIAMOND_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var n := UiKit.label(str(count), &"InkLabel")
	n.add_theme_font_override("font", GameFonts.display())
	n.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	row.add_child(n)
	return row


func _chip_style(chip: PanelContainer, fill: Color, radius: int = 14) -> void:
	var box := UiTheme.flat(fill, radius, 6)
	box.content_margin_left = 2
	box.content_margin_right = 2
	chip.add_theme_stylebox_override("panel", box)


func _shop_button() -> Button:
	_shop = Button.new()
	_shop.name = "Shop"
	_shop.icon = SHOP_ICON
	_shop.text = SHOP
	_shop.focus_mode = Control.FOCUS_NONE
	_shop.add_theme_constant_override("icon_max_width", 22)
	_shop.add_theme_font_override("font", GameFonts.ui(800))
	_shop.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BUTTON)
	var pill := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	pill.content_margin_left = 20
	pill.content_margin_right = 20
	var down := pill.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.PANEL_RAISED
	for state in ["normal", "hover"]:
		_shop.add_theme_stylebox_override(state, pill)
	for state in ["pressed", "hover_pressed"]:
		_shop.add_theme_stylebox_override(state, down)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		_shop.add_theme_color_override(state, UiTokens.ON_PANEL)
	_shop.custom_minimum_size = Vector2(0, 48)
	_shop.pressed.connect(store_pressed.emit)
	return _shop


static func _tier_prize(index: int) -> int:
	return Economy.daily_prize([1, 2, 4][index])


## Which tier chip is lit: the player's own (0, 1, 2) while they hold a prize
## place today, else the top one.
static func tier_index(board: LeaderboardBoard) -> int:
	if board == null or board.me == null:
		return 0
	var rank := board.me.rank
	if rank == 1:
		return 0
	if rank >= 2 and rank <= 3:
		return 1
	if rank >= 4 and rank <= Economy.DAILY_PRIZES.size():
		return 2
	return 0


static func reset_text(board: LeaderboardBoard) -> String:
	if board == null or board.status != LeaderboardBoard.Status.OK or board.resets_in_s < 0:
		return "Resets at midnight"
	return "Resets in %s" % LeaderboardScreen.duration(board.resets_in_s)


## The line under the tiers: where the player stands today and what it takes.
static func daily_line(board: LeaderboardBoard) -> String:
	if board == null:
		return "Looking up your place today..."
	if board.status != LeaderboardBoard.Status.OK:
		return "Your place today shows when you're back online."
	var me := board.me
	if me == null:
		return "Play a run to get on today's board. The top 10 win when the day ends."
	var prize := Economy.daily_prize(me.rank)
	if prize > 0:
		var keep := "on top"
		if me.rank > 3:
			keep = "in the top %d" % Economy.DAILY_PRIZES.size()
		elif me.rank > 1:
			keep = "in the top 3"
		return "You're #%d today. Stay %s to win %d." % [me.rank, keep, prize]
	var last := _last_prize_score(board)
	if last >= 0:
		return (
			"You're #%s today. Beat %s to reach the top 10."
			% [LeaderboardScreen.thousands(me.rank), LeaderboardScreen.thousands(last)]
		)
	return "You're #%s today. The top 10 win diamonds." % LeaderboardScreen.thousands(me.rank)


## The score on the 10th place, or -1 when nobody holds it.
static func _last_prize_score(board: LeaderboardBoard) -> int:
	for e in board.entries:
		if e.rank == Economy.DAILY_PRIZES.size():
			return e.score
	return -1


## Under a milestone: "Won", or the diamonds it pays ("+3").
static func milestone_label(status: EarnStatus, score: int) -> String:
	if status.milestones.has(score):
		return "Won"
	return "+%d" % EarnRules.milestone_prize(score)


static func best_line(status: EarnStatus) -> String:
	var next := EarnRules.next_milestone(status.milestones)
	if next == 0:
		return "All four won. Your best is %d." % status.best
	var prize := SpotAlert.diamonds(EarnRules.milestone_prize(next))
	if status.milestones.is_empty() and status.best <= 0:
		return "Score %d in one run for your first diamond." % next
	var need := next - status.best
	if need <= 0:
		return "Best %d. The prize for %d comes once the run is checked." % [status.best, next]
	return "Best %d. %d more for %s." % [status.best, need, prize]


static func streak_line(status: EarnStatus) -> String:
	var days := status.streak
	if days < 0:
		return "Your streak shows when you're back online."
	if days == 0:
		return (
			"Play one run a day. %d days in a row win %s."
			% [EarnRules.STREAK_DAYS, SpotAlert.diamonds(EarnRules.STREAK_PRIZE)]
		)
	var text := "1 day in a row" if days == 1 else "%d days in a row" % days
	var to_go := EarnRules.days_to_prize(days)
	var wait := "1 day" if to_go == 1 else "%d days" % to_go
	if status.streak_won > 0:
		text += ", %s won. Next one in %s." % [SpotAlert.diamonds(status.streak_won), wait]
	else:
		var more := "1 more day" if to_go == 1 else "%d more days" % to_go
		text += ". %s for %s." % [more, SpotAlert.diamonds(EarnRules.STREAK_PRIZE)]
	if not status.played_today:
		text += " Play today to keep it."
	return text


## For tests.
func daily_text() -> String:
	return _daily_line.text


func best_text() -> String:
	return _best_line.text


func streak_text() -> String:
	return _streak_line.text


func reset_label() -> String:
	return _reset.text


func milestone_labels() -> Array[String]:
	var out: Array[String] = []
	for l in _mile_labels:
		out.append(l.text)
	return out


func streak_dots_filled() -> int:
	var n := 0
	for d in _dots:
		var box := d.get_theme_stylebox("panel") as StyleBoxFlat
		if box.bg_color == UiTokens.INK_LINE:
			n += 1
	return n


func lit_tier() -> int:
	for i in _tiers.size():
		var box := _tiers[i].get_theme_stylebox("panel") as StyleBoxFlat
		if box.bg_color == UiTokens.ACTION:
			return i
	return -1


func bar_ratio() -> float:
	return _bar.ratio


func balance_text() -> String:
	return _balance.amount_text()


func shop_button() -> Button:
	return _shop


func banner_visible() -> bool:
	return _banner.visible


## The best-score bar: an edge track with an ink fill, 8 px tall.
class ProgressLine:
	extends Control
	var ratio := 0.0:
		set(value):
			ratio = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(UiTheme.flat(UiTokens.EDGE, 4, 0), Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			var w := maxf(size.x * ratio, 8.0)
			draw_style_box(UiTheme.flat(UiTokens.INK_LINE, 4, 0), Rect2(0, 0, w, size.y))
