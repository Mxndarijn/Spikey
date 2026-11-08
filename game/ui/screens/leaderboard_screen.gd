class_name LeaderboardScreen
extends Control
## The leaderboards (Sticker Pop): a back button and the title, tabs for the
## four boards (Daily, Tier, All-time, Friends), one outlined line about the
## board (time to reset, players), the top 3 on a podium, the rest in a
## scrolling list, and the player's own row pinned at the bottom with a pencil
## to change their name. Also shows loading, offline, signed-out and empty boards.
## The first visit asks for a leaderboard name. Boards come from a
## LeaderboardService; this screen never decides who is where.

signal closed
signal play_pressed
## The player picked a new leaderboard name (already in the profile).
signal name_changed(player_name: String)

enum View { LOADING, BOARD, EMPTY, OFFLINE, SIGNED_OUT }

const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const EDIT_ICON := preload("res://assets/ui/icons/edit.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const SIDE := 16
## Clear of the floor spikes (tests/unit/test_screen_fit.gd).
const BOTTOM := 40
const LIST_MIN := 140.0
const PINNED_FLYER := 36.0

var view := View.LOADING

var _profile: Profile
var _service: LeaderboardService
var _board_id := LeaderboardService.DAILY
var _board: LeaderboardBoard
var _tabs := {}
var _left := Label.new()
var _right := Label.new()
var _body := VBoxContainer.new()
var _rows: Array[LeaderboardRow] = []
var _podium: Podium
var _pinned_rank: Label
var _pinned_note: Label
var _dialog: NameDialog


func _init(profile: Profile, service: LeaderboardService, board_id: String = "") -> void:
	_profile = profile
	_service = service
	if board_id in LeaderboardService.BOARDS:
		_board_id = board_id


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE + 4)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	margin.add_child(col)
	col.add_child(_header())
	col.add_child(_tab_bar())
	col.add_child(_caption())
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", UiTokens.SPACE_2)
	col.add_child(_body)
	_service.board_loaded.connect(_on_board_loaded)
	select_board(_board_id)
	if _profile.leaderboard_name.is_empty():
		open_name_dialog()


func _header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.theme_type_variation = &"RoundButton"
	back.icon = BACK_ICON
	back.tooltip_text = "Back"
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(closed.emit)
	row.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 32)
	title.text = "Leaderboards"
	var tilt := Tilt.new(title, -3.0)
	tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tilt)
	return row


func _tab_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	bar.add_child(tabs)
	var group := ButtonGroup.new()
	for id in LeaderboardService.BOARDS:
		var tab := Button.new()
		tab.theme_type_variation = &"TabButton"
		tab.add_theme_font_size_override("font_size", 13)
		_tight(tab)
		tab.text = LeaderboardService.TITLES[id]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(select_board.bind(id))
		_tabs[id] = tab
		tabs.add_child(tab)
	return bar


## Tabs keep only a little padding. Copies the style from UiTheme directly: the
## tab isn't in the tree yet, so its own get_theme_stylebox() would be Godot's.
func _tight(tab: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := UiTheme.get_theme().get_stylebox(state, &"TabButton").duplicate() as StyleBox
		box.content_margin_left = 2
		box.content_margin_right = 2
		tab.add_theme_stylebox_override(state, box)


## One outlined line on the sky: what the board is on the left, the count right.
func _caption() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l in [_left, _right]:
		l.theme_type_variation = &"SkyCaption"
		l.add_theme_font_size_override("font_size", 14)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_left)
	row.add_child(_right)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_right", 2)
	pad.add_child(row)
	return pad


## Shows a board's tab as selected, shows loading, and asks for the board.
func select_board(id: String) -> void:
	if not id in LeaderboardService.BOARDS:
		return
	_board_id = id
	(_tabs[id] as Button).button_pressed = true
	_show_loading()
	_service.request_board(id)


func _on_board_loaded(board: LeaderboardBoard) -> void:
	if board.id == _board_id:
		show_board(board)


## Draws a board: the podium, the list and the pinned row, or the matching state.
func show_board(board: LeaderboardBoard) -> void:
	_board = board
	_clear()
	match board.status:
		LeaderboardBoard.Status.OFFLINE:
			_set_caption("", "")
			_show_message(
				View.OFFLINE,
				"Leaderboards need an internet connection",
				"Keep playing. Your runs are saved and go on the boards when you are back online.",
				"Try again",
				select_board.bind(_board_id)
			)
			return
		LeaderboardBoard.Status.SIGNED_OUT:
			_set_caption("", "")
			_show_message(
				View.SIGNED_OUT,
				"Sign in to see your friends",
				"Friends come from %s. Every other board works without signing in." % platform(),
				"Sign in with %s" % platform(),
				_sign_in
			)
			return
	_set_caption(caption_left(board), caption_right(board))
	_podium = Podium.new(board.entries)
	_body.add_child(_podium)
	if board.is_empty():
		view = View.EMPTY
		_body.add_child(_empty_card())
		return
	view = View.BOARD
	_body.add_child(_list(board))
	_body.add_child(_pinned(board))


func _show_loading() -> void:
	view = View.LOADING
	_board = null
	_clear()
	_set_caption(LeaderboardService.TITLES[_board_id], "")
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"StickerPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.theme_type_variation = &"MutedLabel"
	l.text = "Loading the %s board" % (LeaderboardService.TITLES[_board_id] as String).to_lower()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	_body.add_child(panel)


func _clear() -> void:
	_rows.clear()
	_podium = null
	_pinned_rank = null
	_pinned_note = null
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func _set_caption(left: String, right: String) -> void:
	_left.text = left
	_right.text = right


func _list(board: LeaderboardBoard) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, 3)
	)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, LIST_MIN)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for i in range(3, board.entries.size()):
		var row := LeaderboardRow.new(board.entries[i])
		_rows.append(row)
		rows.add_child(row)
	return panel


## The player's own row: rank, flyer, name with what the rank means, the pencil
## and the score. No score yet: "#-" and why.
func _pinned(board: LeaderboardBoard) -> Control:
	var panel := PanelContainer.new()
	var box := UiTheme.sticker(UiTheme.SELECTED_FILL, 16, Vector2(0, 5), 4, UiTheme.BORDER_BOLD)
	box.content_margin_left = UiTokens.SPACE_2
	box.content_margin_right = UiTokens.SPACE_3
	panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	panel.add_child(row)
	var me := board.me
	_pinned_rank = Label.new()
	_pinned_note = Label.new()
	_pinned_rank.theme_type_variation = &"InkLabel"
	_pinned_rank.add_theme_font_size_override("font_size", 17)
	_pinned_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pinned_rank.text = _rank_text(me.rank) if me != null else "#–"
	row.add_child(_pinned_rank)
	var flyer := LeaderboardRow.flyer_texture(_profile.equipped_id(Catalog.FLYER))
	row.add_child(LeaderboardRow.icon(flyer, PINNED_FLYER))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -4)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := Label.new()
	name_label.theme_type_variation = &"SmallNameLabel"
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.text = (
		_profile.leaderboard_name if not _profile.leaderboard_name.is_empty() else "You"
	)
	words.add_child(name_label)
	_pinned_note.theme_type_variation = &"MutedLabel"
	_pinned_note.add_theme_font_size_override("font_size", 12)
	_pinned_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pinned_note.custom_minimum_size = Vector2(60, 0)
	_pinned_note.text = pinned_note(board)
	words.add_child(_pinned_note)
	row.add_child(words)
	var edit := Button.new()
	edit.theme_type_variation = &"RoundButton"
	edit.icon = EDIT_ICON
	edit.tooltip_text = "Change your leaderboard name"
	edit.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.focus_mode = Control.FOCUS_NONE
	edit.pressed.connect(open_name_dialog)
	row.add_child(edit)
	if me != null:
		var score := Label.new()
		score.theme_type_variation = &"CoinLabel"
		score.add_theme_font_size_override("font_size", 24)
		score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		score.text = str(me.score)
		row.add_child(score)
	return panel


## The board right after it starts over: an invitation to take first place.
func _empty_card() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"StickerPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.add_theme_font_size_override("font_size", 21)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(240, 0)
	title.text = "Nobody has played today yet"
	col.add_child(title)
	var body := Label.new()
	body.theme_type_variation = &"MutedLabel"
	body.add_theme_font_size_override("font_size", 14)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(240, 0)
	body.text = "Play a run now and you start the day in first place."
	col.add_child(body)
	var play := Button.new()
	play.theme_type_variation = &"ActionButton"
	play.text = "Play"
	play.icon = PLAY_ICON
	play.custom_minimum_size = Vector2(0, 56)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(play_pressed.emit)
	col.add_child(play)
	return panel


## Offline or signed out: what happened and the one thing to do about it.
func _show_message(
	which: View, title_text: String, body_text: String, action: String, on_press: Callable
) -> void:
	view = which
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BigPanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	panel.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.add_theme_font_size_override("font_size", 23)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(240, 0)
	title.text = title_text
	col.add_child(title)
	var body := Label.new()
	body.theme_type_variation = &"MutedLabel"
	body.add_theme_font_size_override("font_size", 14)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(240, 0)
	body.text = body_text
	col.add_child(body)
	var button := Button.new()
	button.theme_type_variation = &"ActionButton"
	button.add_theme_font_size_override("font_size", 18)
	button.text = action
	button.custom_minimum_size = Vector2(0, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	col.add_child(button)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_top", UiTokens.SPACE_6)
	top.add_child(panel)
	_body.add_child(top)


func _sign_in() -> void:
	_service.sign_in()
	select_board(_board_id)


func open_name_dialog() -> void:
	if _dialog != null:
		return
	_dialog = NameDialog.new(_profile.leaderboard_name, _profile.equipped_id(Catalog.FLYER))
	_dialog.saved.connect(_on_name_saved)
	_dialog.cancelled.connect(_close_name_dialog)
	add_child(_dialog)


func _on_name_saved(player_name: String) -> void:
	_profile.leaderboard_name = player_name
	_close_name_dialog()
	name_changed.emit(player_name)
	select_board(_board_id)


func _close_name_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


## Game Center on Apple devices, Play Games everywhere else.
static func platform() -> String:
	return "Game Center" if OS.get_name() in ["iOS", "macOS"] else "Play Games"


static func caption_left(board: LeaderboardBoard) -> String:
	match board.id:
		LeaderboardService.DAILY:
			return "Resets in %s" % duration(board.resets_in_s)
		LeaderboardService.TIER:
			return "%s tier" % board.tier_name
		LeaderboardService.ALL_TIME:
			return "Best run per player"
		LeaderboardService.FRIENDS:
			var n := board.entries.size() - (1 if board.me != null else 0)
			return "%d friend%s" % [n, "" if n == 1 else "s"]
	return ""


static func caption_right(board: LeaderboardBoard) -> String:
	match board.id:
		LeaderboardService.TIER:
			return "Top 10 move up Monday"
		LeaderboardService.FRIENDS:
			return "Best runs ever"
	if board.is_empty():
		return "No players yet"
	return "%s players" % thousands(board.players)


## What the player's rank means, or why there is none.
static func pinned_note(board: LeaderboardBoard) -> String:
	var me := board.me
	if me == null:
		return "No run today yet" if board.id == LeaderboardService.DAILY else "No runs yet"
	match board.id:
		LeaderboardService.DAILY:
			return "of %s today" % thousands(board.players)
		LeaderboardService.TIER:
			return "of %d in %s tier" % [board.players, board.tier_name]
		LeaderboardService.ALL_TIME:
			var pct := maxi(ceili(me.rank * 100.0 / maxi(board.players, 1)), 1)
			return "Top %d%% of all players" % pct
		LeaderboardService.FRIENDS:
			return "of %d friends" % board.players
	return ""


## "9h 12m" for an hour or more, else "23m 41s".
static func duration(seconds: int) -> String:
	var s := maxi(seconds, 0)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	return "%dm %ds" % [s / 60, s % 60]


## 18402 -> "18,402".
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


static func _rank_text(rank: int) -> String:
	return "#" + thousands(rank)


func board_id() -> String:
	return _board_id


func board() -> LeaderboardBoard:
	return _board


func rows() -> Array[LeaderboardRow]:
	return _rows


func podium() -> Podium:
	return _podium


func caption_text() -> String:
	return "%s | %s" % [_left.text, _right.text]


func pinned_rank_text() -> String:
	return _pinned_rank.text if _pinned_rank != null else ""


func pinned_note_text() -> String:
	return _pinned_note.text if _pinned_note != null else ""


func name_dialog() -> NameDialog:
	return _dialog


func tab_names() -> Array[String]:
	var out: Array[String] = []
	for id: String in _tabs:
		out.append((_tabs[id] as Button).text)
	return out
