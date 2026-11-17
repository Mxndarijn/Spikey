class_name BattleScreen
extends Control
## One battle (docs/DUEL_MODE.md, screens B3, B4, B6, B7 and K1): the back
## arrow, the rival (with the BOT pill for a bot) and the menu button at the top;
## on the room the score ("You 2 – 2 Mira"), "First to 6" and the rounds as
## squares; one paper card that says what happens now; one round main action:
##   your turn   the round's intro: the rival's score to beat (or that the round
##               is blind, or that you go first) and Play, one try
##   their turn  waiting since when, and Nudge when it may
##   waiting     an invite's code to send (Share, Copy code), or "looking for a rival"
##   finished    who won and Rematch
## A line over the card tells what just happened (a round's result, a lost run).

signal closed
signal play_pressed(round_number: int)
signal menu_pressed
signal nudge_pressed
signal rematch_pressed
signal copy_pressed(text: String)
## Share: the phone's share sheet with the invite (BattleFlow; copy off a phone).
signal share_pressed(text: String)
signal refresh_requested

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const REPLAY_ICON := preload("res://assets/ui/icons/restart.svg")
const MENU_ICON := preload("res://assets/ui/icons/settings.svg")
const SIDE := UiKit.SCREEN_SIDE
const TOP := UiKit.SCREEN_TOP
const SCORE_Y := 100.0
const SCORE_SIZE := 34
const RULE_Y := 146.0
const ROUNDS_Y := 172.0
const CARD_Y := 250.0
const LINE_W := 280.0
## The link a friend's phone opens (App Links, Universal Links).
const LINK := "https://flapjaw.mn-platform.tech/battle/%s"
const DUEL_LINK := "https://flapjaw.mn-platform.tech/duel/%s"

var view: BattleView
## An invite's code, known only to the phone that made it.
var code := ""
var _head: Control
var _score: Label
var _rule: Label
var _rounds_at: Control
var _notice: Label
var _title: Label
var _body: Label
var _big: Label
var _extra: Button
var _primary: Button
var _pill: Label
var _card_box: Control


func _init(p_view: BattleView, p_code: String = "") -> void:
	view = p_view
	code = p_code
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var menu := UiKit.icon_button(MENU_ICON, "Battle menu", &"RoundButton", UiKit.ICON_BUTTON)
	menu.name = "Menu"
	menu.pressed.connect(menu_pressed.emit)
	_head = UiKit.header(view.rival_label(), closed.emit, menu)
	add_child(_head)
	_head.anchor_right = 1.0
	_head.offset_left = SIDE
	_head.offset_right = -SIDE
	_head.offset_top = TOP
	_head.offset_bottom = TOP + UiKit.HEADER_HEIGHT
	_score = UiKit.label("", &"RoomStat")
	_score.add_theme_font_size_override("font_size", SCORE_SIZE)
	UiKit.across(self, _score, SCORE_Y)
	_rule = UiKit.label("", &"SkyCaption")
	UiKit.across(self, _rule, RULE_Y)
	_rounds_at = Control.new()
	_rounds_at.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rounds_at)
	_rounds_at.anchor_right = 1.0
	_rounds_at.offset_left = SIDE + 20
	_rounds_at.offset_right = -SIDE - 20
	_rounds_at.offset_top = ROUNDS_Y
	_rounds_at.offset_bottom = CARD_Y - 8
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	card.add_child(col)
	_notice = UiKit.wrapped("", &"InkLabel", LINE_W)
	_notice.name = "Notice"
	_notice.visible = false
	col.add_child(_notice)
	_title = UiKit.wrapped("", &"NameLabel", LINE_W)
	_title.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_HEADING)
	col.add_child(_title)
	_big = UiKit.label("", &"NameLabel")
	_big.name = "Big"
	_big.add_theme_font_size_override("font_size", 48)
	col.add_child(_big)
	_body = UiKit.wrapped("", &"MutedLabel", LINE_W)
	col.add_child(_body)
	_extra = UiKit.row_button("", UiTokens.PANEL_RAISED)
	_extra.name = "Extra"
	_extra.pressed.connect(_on_extra)
	col.add_child(_extra)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE + 8)
	margin.add_theme_constant_override("margin_right", SIDE + 8)
	margin.add_child(card)
	UiKit.across(self, margin, CARD_Y)
	_card_box = margin
	_primary = UiKit.primary(PLAY_ICON, "Play")
	_primary.name = "Primary"
	_primary.pressed.connect(_on_primary)
	UiKit.place_primary(self, _primary)
	show_view(view)


## The battle as the server sent it last.
func show_view(v: BattleView) -> void:
	view = v
	if _score == null:
		return
	(_head.get_node("Title") as Label).text = v.rival_label()
	_score.text = "You %d – %d" % [v.wins_me, v.wins_them]
	_rule.text = "First to %d round wins" % v.first_to
	for c in _rounds_at.get_children():
		c.queue_free()
	var strip := BattleKit.rounds_strip(v)
	_rounds_at.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if v.rival_bot and v.rival_name != "" and _pill == null:
		# Under the name in the header: a bot always says so.
		_pill = BattleKit.bot_pill()
		_head.add_child(_pill)
		_pill.position = Vector2(UiKit.TITLE_X - SIDE, UiKit.HEADER_HEIGHT - 6)
	_big.visible = false
	_extra.visible = false
	_primary.disabled = false
	_primary.visible = true
	if v.status == BattleView.CLOSED:
		_say("Closed, no result", "This battle ended with no result. It counts for nobody.")
		_primary.visible = false
	elif v.status == BattleView.FINISHED:
		_show_result(v)
	elif v.status == BattleView.WAITING and not v.my_turn():
		_show_waiting(v)
	elif v.my_turn():
		_show_turn(v)
	else:
		_say(
			"Waiting for %s" % v.rival_label(),
			"%s plays next. Last move %s." % [v.rival_label(), MatchRules.since_text(v.last_move_s)]
		)
		_primary.visible = false
		if v.can_nudge:
			_extra_row("Nudge %s" % v.rival_name)


func _show_turn(v: BattleView) -> void:
	_primary.text = "Play"
	_primary.icon = PLAY_ICON
	if v.play_role == "answer" and v.rival_pending:
		_say("Round %d" % v.play_round, "Checking %s's run. It takes a moment." % v.rival_name)
		_primary.disabled = true
		_extra_row("Check again")
	elif v.play_role == "answer" and v.play_blind:
		_say(
			"Round %d decides it" % v.play_round,
			"%s has played. You'll see the run after yours. One try." % v.rival_name
		)
	elif v.play_role == "answer" and v.rival_score() >= 0:
		_say(
			"Round %d · To beat" % v.play_round,
			"%s's score. You'll see their run as you fly. One try." % v.rival_name
		)
		_big.text = str(v.rival_score())
		_big.add_theme_font_size_override("font_size", 48)
		_big.visible = true
	elif v.play_blind:
		_say(
			"Round %d decides it" % v.play_round,
			"You go first. Neither of you sees the other's run before playing. One try."
		)
	else:
		var who := v.rival_label() if v.rival_name != "" else "Your rival"
		_say("Round %d · You go first" % v.play_round, "%s will see your run. One try." % who)


func _show_waiting(v: BattleView) -> void:
	_primary.visible = false
	if not code.is_empty():
		_say("Send this code", "Good for 7 days, for one friend. You've played round 1.")
		_big.text = "%s·%s" % [code.left(3), code.substr(3)]
		_big.add_theme_font_size_override("font_size", 34)
		_big.visible = true
		_extra_row("Copy code and link")
		_primary.text = "Share"
		_primary.icon = null
		_primary.visible = true
	elif v.random:
		_say(
			"Looking for a rival", "A player takes your battle soon, or a bot when no one is free."
		)
	else:
		_say("Waiting for your friend", "The battle starts when they type your code.")


func _show_result(v: BattleView) -> void:
	var title := "Draw"
	if v.winner == "me":
		title = "You win"
	elif v.winner == "them":
		title = "%s wins" % v.rival_label()
	var how := (
		"%s resigned. " % v.rival_label() if v.ended_by == "resigned" and v.winner == "me" else ""
	)
	if v.ended_by == "resigned" and v.winner == "them":
		how = "You resigned. "
	_say(title, "%s%d – %d. Each square opens its round." % [how, v.wins_me, v.wins_them])
	_primary.text = "Rematch"
	_primary.icon = REPLAY_ICON


func _say(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	UiKit.fit_height(_card_box)


func _extra_row(text: String) -> void:
	_extra.text = text
	_extra.visible = true
	UiKit.fit_height(_card_box)


## A line over the card: a round's result, a lost run, a round dealt again.
func set_notice(text: String) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()
	UiKit.fit_height(_card_box)


func _on_primary() -> void:
	if view.status == BattleView.WAITING and not code.is_empty():
		share_pressed.emit(invite_text(code))
	elif view.status == BattleView.FINISHED:
		rematch_pressed.emit()
	elif view.my_turn():
		play_pressed.emit(view.play_round)


func _on_extra() -> void:
	if view.status == BattleView.WAITING and not code.is_empty():
		copy_pressed.emit(invite_text(code))
	elif view.my_turn() and view.rival_pending:
		refresh_requested.emit()
	elif view.can_nudge:
		nudge_pressed.emit()


## What Copy and Share send a friend: "Battle me in Flapjaw! <link> (code KD7WQ3)".
static func invite_text(p_code: String, duel: bool = false) -> String:
	if duel:
		return "Duel me in Flapjaw! %s (code %s)" % [DUEL_LINK % p_code, p_code]
	return "Battle me in Flapjaw! %s (code %s)" % [LINK % p_code, p_code]


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


func big_text() -> String:
	return _big.text if _big.visible else ""


func notice_text() -> String:
	return _notice.text if _notice.visible else ""


func primary() -> Button:
	return _primary


func extra() -> Button:
	return _extra
