class_name DuelScreen
extends Control
## Duel (docs/DUEL_MODE.md, screens D1, D2, D4 and D5): one screen that says
## where the duel is, the back arrow at the top and one round main action:
##   start      Find a rival, Invite a friend, or a friend's code to type
##   finding    the time looking, Cancel, and after 30 s a Battle instead
##   invite     the code to send, Share, Copy, Cancel
##   countdown  the round, both names and the score, 3-2-1
##   between    who won the round and by how much, the next round in 5
##   waiting    you're down; the rival still flies
##   result     You win 2-1 (or not), Rematch
## The live round itself (D3) is the run, with the rival's bird beside yours.

signal closed
signal find_pressed
signal invite_pressed
signal join_pressed(code: String)
signal cancel_pressed
signal rematch_pressed
signal battle_pressed
signal copy_pressed(text: String)
## Share: the phone's share sheet with the invite (DuelFlow; copy off a phone).
signal share_pressed(text: String)

enum State { START, FINDING, INVITE, COUNTDOWN, BETWEEN, WAITING, RESULT }

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const REPLAY_ICON := preload("res://assets/ui/icons/restart.svg")
const SIDE := UiKit.SCREEN_SIDE
const TOP := UiKit.SCREEN_TOP
const CARD_Y := 120.0
const LINE_W := 280.0
## After this long in the queue, offer a Battle instead.
const BATTLE_AFTER_S := 30.0
const RULES := "Live 1v1 · Best of 3 · No revives"

var state := State.START
var _card_col: VBoxContainer
var _card_box: Control
var _title: Label
var _body: Label
var _big: Label
var _a: Button
var _b: Button
var _field := LineEdit.new()
var _primary: Button
var _finding_s := 0.0
var _code := ""
var _updating := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var head := UiKit.header("Duel", closed.emit)
	add_child(head)
	head.anchor_right = 1.0
	head.offset_left = SIDE
	head.offset_right = -SIDE
	head.offset_top = TOP
	head.offset_bottom = TOP + UiKit.HEADER_HEIGHT
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"Card"
	_card_col = VBoxContainer.new()
	_card_col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(_card_col)
	_title = UiKit.wrapped("", &"NameLabel", LINE_W)
	_title.add_theme_font_size_override("font_size", 22)
	_card_col.add_child(_title)
	_big = UiKit.label("", &"NameLabel")
	_big.name = "Big"
	_big.add_theme_font_size_override("font_size", 56)
	_card_col.add_child(_big)
	_body = UiKit.wrapped("", &"MutedLabel", LINE_W)
	_card_col.add_child(_body)
	_a = UiKit.action_button("")
	_a.name = "A"
	_a.pressed.connect(_on_a)
	_card_col.add_child(_a)
	_b = UiKit.row_button("", UiTokens.PANEL_RAISED)
	_b.name = "B"
	_b.pressed.connect(_on_b)
	_card_col.add_child(_b)
	var row := HBoxContainer.new()
	row.name = "CodeRow"
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_field.name = "Code"
	_field.placeholder_text = "Friend's code"
	_field.max_length = 7
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	_field.text_submitted.connect(func(_t: String) -> void: _join())
	row.add_child(_field)
	var join := UiKit.text_button("Join", &"InkButton")
	UiKit.soft_button(join)
	join.custom_minimum_size = Vector2(76, UiTokens.SIZE_TAP_MIN)
	join.name = "Join"
	join.pressed.connect(_join)
	row.add_child(join)
	_card_col.add_child(row)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE + 8)
	margin.add_theme_constant_override("margin_right", SIDE + 8)
	margin.add_child(card)
	UiKit.across(self, margin, CARD_Y)
	_card_box = margin
	_primary = UiKit.primary(PLAY_ICON, "Find")
	_primary.name = "Primary"
	_primary.pressed.connect(_on_primary)
	UiKit.place_primary(self, _primary)
	show_start()


func _process(delta: float) -> void:
	if state != State.FINDING:
		return
	_finding_s += delta
	_big.text = "%d:%02d" % [int(_finding_s) / 60, int(_finding_s) % 60]
	# No Battle to offer while it is paused (GameModes.battle_enabled).
	_b.visible = _finding_s >= BATTLE_AFTER_S and GameModes.battle_enabled


func _show(title: String, big: String, body: String, a: String, b: String, code_row: bool) -> void:
	_title.text = title
	_big.text = big
	_big.visible = not big.is_empty()
	_body.text = body
	_a.text = a
	_a.visible = not a.is_empty()
	_b.text = b
	_b.visible = not b.is_empty()
	_card_col.get_node("CodeRow").visible = code_row
	_primary.visible = false
	UiKit.fit_height(_card_box)


func show_start() -> void:
	_big.add_theme_font_size_override("font_size", 56)
	state = State.START
	_show(
		"Duel a rival",
		"",
		RULES + ". You both fly the same map at the same time.",
		"Invite a friend",
		"",
		true
	)
	_primary.text = "Find"
	_primary.icon = PLAY_ICON
	_primary.visible = true


func show_finding() -> void:
	_big.add_theme_font_size_override("font_size", 56)
	state = State.FINDING
	_finding_s = 0.0
	_show(
		"Finding a rival",
		"0:00",
		"Someone on your version, near your level.",
		"Cancel",
		"Play a Battle instead",
		false
	)
	_b.visible = false


func show_invite(code: String) -> void:
	_big.add_theme_font_size_override("font_size", 28)
	state = State.INVITE
	_code = code
	_show(
		"Send this code",
		"%s·%s" % [code.left(3), code.substr(3)],
		"Good for 10 minutes. Keep this screen open: the duel starts when your friend joins.",
		"Copy code",
		"Cancel",
		false
	)
	_primary.text = "Share"
	_primary.icon = null
	_primary.visible = true


func show_countdown(
	round_number: int, rival: String, wins_me: int, wins_them: int, left_s: int
) -> void:
	_big.add_theme_font_size_override("font_size", 72)
	state = State.COUNTDOWN
	_show(
		"Round %d" % round_number,
		str(left_s),
		"You %d – %d %s. Tap to fly when it starts." % [wins_me, wins_them, rival],
		"",
		"",
		false
	)


func show_between(text: String, my_score: int, their_score: int, rival: String) -> void:
	_big.add_theme_font_size_override("font_size", 36)
	state = State.BETWEEN
	_show(
		text,
		"%d – %d" % [my_score, their_score],
		"You and %s. The next round starts in 5." % rival,
		"",
		"",
		false
	)


## `left_app`: the server put this bird down because the phone stopped
## (the app went to the background, or the connection).
func show_waiting(my_score: int, rival: String, left_app: bool = false) -> void:
	_big.add_theme_font_size_override("font_size", 56)
	state = State.WAITING
	var why := ""
	if left_app:
		why = "You left the app, so your bird is down: a Duel doesn't pause. "
	_show(
		"You're down at %d" % my_score,
		"",
		why + "%s is still flying and needs %d to win the round." % [rival, my_score + 1],
		"",
		"",
		false
	)


func show_result(winner: String, wins_me: int, wins_them: int, rival: String, left: bool) -> void:
	_big.add_theme_font_size_override("font_size", 48)
	state = State.RESULT
	var title := "Draw"
	if winner == "me":
		title = "You win"
	elif winner == "them":
		title = "%s wins" % rival
	var how := ""
	if left:
		how = "%s left the duel. " % rival if winner == "me" else "You left the duel. "
	_show(
		title,
		"%d – %d" % [wins_me, wins_them],
		how + "Rematch asks %s to play again." % rival,
		"",
		"",
		false
	)
	_primary.text = "Rematch"
	_primary.icon = REPLAY_ICON
	_primary.visible = true


## This app is older than the server's game: Duel waits for the update.
func show_update() -> void:
	_big.add_theme_font_size_override("font_size", 56)
	state = State.START
	_show(GameModes.UPDATE_LINE, "", BattleService.UPDATE, "", "", false)
	_primary.text = GameModes.UPDATE
	_primary.visible = true
	_updating = true


func set_line(text: String) -> void:
	_body.text = text


func _on_primary() -> void:
	if _updating:
		StoreLink.open()
		return
	match state:
		State.START:
			find_pressed.emit()
		State.INVITE:
			share_pressed.emit(BattleScreen.invite_text(_code, true))
		State.RESULT:
			rematch_pressed.emit()


func _on_a() -> void:
	match state:
		State.START:
			invite_pressed.emit()
		State.FINDING:
			cancel_pressed.emit()
		State.INVITE:
			copy_pressed.emit(BattleScreen.invite_text(_code, true))


func _on_b() -> void:
	match state:
		State.FINDING:
			battle_pressed.emit()
		State.INVITE:
			cancel_pressed.emit()


func _join() -> void:
	var code := NewBattleSheet.clean(_field.text)
	if code.length() == NewBattleSheet.CODE_LENGTH:
		join_pressed.emit(code)


func title_text() -> String:
	return _title.text


func big_text() -> String:
	return _big.text if _big.visible else ""


func body_text() -> String:
	return _body.text


func a_button() -> Button:
	return _a


func b_button() -> Button:
	return _b


func primary() -> Button:
	return _primary


func field() -> LineEdit:
	return _field
