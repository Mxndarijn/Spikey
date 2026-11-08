class_name LeaderboardScreen
extends Control
## The leaderboards (minimal kit): the back arrow and the title, a paper tab bar
## for the boards (LeaderboardService.BOARDS: Daily and All-time), one plain line
## about the board (time to reset, players), the top 3 on a podium, the rest as
## paper pill rows in a scrolling list, and the player's own gold row pinned at
## the bottom with a pencil to change their name. Also shows loading, offline,
## signed-out and empty boards.
## The first visit asks for a leaderboard name. Boards come from a
## LeaderboardService; this screen never decides who is where.

signal closed
signal play_pressed
## The player picked a new leaderboard name (already in the profile).
signal name_changed(player_name: String)
## Watch replay was pressed and the run arrived (SupabaseLeaderboard.parse_run()
## shape; {} when it could not be loaded). main.gd plays it back.
signal replay_requested(run: Dictionary)

enum View { LOADING, BOARD, EMPTY, OFFLINE, SIGNED_OUT }

const EDIT_ICON := preload("res://assets/ui/icons/edit.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const SIDE := 14
## Clear of the floor spikes (tests/unit/test_screen_fit.gd).
const BOTTOM := 40
const LIST_MIN := 140.0
const PINNED_FLYER := 32.0

var view := View.LOADING

var _profile: Profile
var _service: LeaderboardService
var _board_id := LeaderboardService.DAILY
var _board: LeaderboardBoard
var _tabs := {}
var _left := ""
var _right := ""
var _caption_label := Label.new()
var _body := VBoxContainer.new()
var _rows: Array[LeaderboardRow] = []
var _podium: Podium
var _pinned_rank: Label
var _pinned_note: Label
var _dialog: NameDialog
## The "Watch replay" sheet and the run it is for (0: closed).
var _sheet: Control
## The board's row list; a drag on it is not a tap on a row.
var _list_scroll: SmoothScroll
var _sheet_run := 0
var _sheet_status: Label


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
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	margin.add_child(col)
	col.add_child(UiKit.header("Leaderboards", closed.emit))
	col.add_child(_tab_bar())
	col.add_child(_caption())
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", UiTokens.SPACE_2)
	col.add_child(_body)
	_service.board_loaded.connect(_on_board_loaded)
	_service.run_loaded.connect(_on_run_loaded)
	select_board(_board_id)
	if _profile.leaderboard_name.is_empty():
		open_name_dialog()


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


## One plain centred line on the room: what the board is, then the count.
func _caption() -> Control:
	_caption_label.theme_type_variation = &"RoomMuted"
	_caption_label.add_theme_font_size_override("font_size", 13)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption_label.custom_minimum_size = Vector2(60, 0)
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _caption_label


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
	var spots := _podium.spots()
	for i in spots.size():
		if spots[i] != null:
			_tappable(_podium.get_child(i) as Control, spots[i])
	if board.is_empty():
		view = View.EMPTY
		_body.add_child(_empty_card(board.id == LeaderboardService.DAILY))
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
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(0, 120)
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
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
	_left = left
	_right = right
	var parts := PackedStringArray()
	for part in [left, right]:
		if not (part as String).is_empty():
			parts.append(part)
	_caption_label.text = ", ".join(parts)


func _list(board: LeaderboardBoard) -> Control:
	var scroll := SmoothScroll.new()
	scroll.blocked = func() -> bool: return _dialog != null or _sheet != null
	_list_scroll = scroll
	scroll.custom_minimum_size = Vector2(0, LIST_MIN)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", UiTokens.SPACE_2)
	scroll.add_child(rows)
	for i in range(3, board.entries.size()):
		var row := LeaderboardRow.new(board.entries[i])
		_tappable(row, board.entries[i])
		_rows.append(row)
		rows.add_child(row)
	rows.add_child(UiKit.spacer(FadeMask.FADE))
	return FadeMask.new(scroll)


## The player's own row, a gold pill: rank, flyer, "You (name)" over what the
## rank means, the pencil and the score. No score yet: "#-" and why.
func _pinned(board: LeaderboardBoard) -> Control:
	var panel := PanelContainer.new()
	var box := LeaderboardRow.pill(UiTokens.ACTION)
	box.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(0, LeaderboardRow.HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	panel.add_child(row)
	var me := board.me
	_pinned_rank = LeaderboardRow.rank_label(_rank_text(me.rank) if me != null else "#–")
	row.add_child(_pinned_rank)
	var flyer := LeaderboardRow.flyer_texture(_profile.equipped_id(Catalog.FLYER))
	row.add_child(LeaderboardRow.icon(flyer, PINNED_FLYER))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -3)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var player := _profile.leaderboard_name
	words.add_child(
		LeaderboardRow.name_label("You (%s)" % player if not player.is_empty() else "You")
	)
	_pinned_note = Label.new()
	_pinned_note.theme_type_variation = &"CaptionLabel"
	_pinned_note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	_pinned_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pinned_note.custom_minimum_size = Vector2(40, 0)
	_pinned_note.text = pinned_note(board)
	words.add_child(_pinned_note)
	row.add_child(words)
	var edit := UiKit.icon_button(
		EDIT_ICON, "Change your leaderboard name", &"InkButton", UiTokens.SIZE_TAP_MIN
	)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		edit.add_theme_color_override(state, UiTokens.ON_ACTION)
	edit.add_theme_color_override("icon_hover_pressed_color", UiTokens.ON_ACTION)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.pressed.connect(open_name_dialog)
	row.add_child(edit)
	if me != null:
		row.add_child(LeaderboardRow.score_label(me.score))
	return panel


## A board nobody is on yet (Daily right after midnight): an invitation to be first.
func _empty_card(daily: bool) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.add_theme_font_size_override("font_size", 21)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(240, 0)
	title.text = "Nobody has played today yet" if daily else "Nobody is on the board yet"
	col.add_child(title)
	var body := Label.new()
	body.theme_type_variation = &"CaptionLabel"
	body.add_theme_font_size_override("font_size", 14)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(240, 0)
	body.text = (
		"Play a run now and you start the day in first place."
		if daily
		else "Play a run and you are the first one on it."
	)
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
	body.theme_type_variation = &"CaptionLabel"
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
	# Long labels ("Sign in with Game Center") wrap instead of widening the card.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	col.add_child(button)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_top", UiTokens.SPACE_6)
	top.add_child(panel)
	_body.add_child(top)


## A row or podium place with a stored run opens the replay sheet when tapped.
## Sample boards and runs from before replays have no run id, so nothing happens.
func _tappable(target: Control, e: LeaderboardBoard.Entry) -> void:
	if e.run_id <= 0:
		return
	target.mouse_filter = Control.MOUSE_FILTER_PASS
	target.tooltip_text = "Watch the run"
	target.gui_input.connect(_on_tap.bind(e))


func _on_tap(event: InputEvent, e: LeaderboardBoard.Entry) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if is_instance_valid(_list_scroll) and _list_scroll.swallow_tap():
			return
		open_replay(e)


## The small sheet for one run: whose it is, the score, Watch replay and Close.
func open_replay(e: LeaderboardBoard.Entry) -> void:
	if e.run_id <= 0 or _dialog != null:
		return
	close_replay()
	_sheet_run = e.run_id
	_sheet = Control.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	_sheet.add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_bottom", BOTTOM + 8)
	_sheet.add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(LeaderboardRow.icon(LeaderboardRow.flyer_texture(e.flyer_id), 44))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.text = "Your run" if e.is_me else "%s's run" % e.player_name
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(120, 0)
	words.add_child(title)
	var score := Label.new()
	score.theme_type_variation = &"InkLabel"
	score.text = "#%d, %d points" % [e.rank, e.score]
	words.add_child(score)
	head.add_child(words)
	col.add_child(head)
	_sheet_status = Label.new()
	_sheet_status.theme_type_variation = &"InkLabel"
	_sheet_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_status.custom_minimum_size = Vector2(240, 0)
	_sheet_status.text = "Watch it in the room with their own flyer and world."
	col.add_child(_sheet_status)
	var watch := Button.new()
	watch.theme_type_variation = &"ActionButton"
	watch.text = "Watch replay"
	watch.icon = PLAY_ICON
	watch.custom_minimum_size = Vector2(0, 56)
	watch.focus_mode = Control.FOCUS_NONE
	watch.pressed.connect(_watch.bind(watch))
	col.add_child(watch)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_replay)
	col.add_child(close)
	add_child(_sheet)


func _on_scrim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		close_replay()


func _watch(button: Button) -> void:
	button.disabled = true
	_sheet_status.text = "Loading the replay"
	_service.request_run(_sheet_run)


func _on_run_loaded(run_id: int, run: Dictionary) -> void:
	if _sheet == null or run_id != _sheet_run:
		return
	close_replay()
	replay_requested.emit(run)


func close_replay() -> void:
	if _sheet != null:
		_sheet.queue_free()
	_sheet = null
	_sheet_status = null
	_sheet_run = 0


## The open replay sheet, for tests (null when closed).
func replay_sheet() -> Control:
	return _sheet


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
	return "%s | %s" % [_left, _right]


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
