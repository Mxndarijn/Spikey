class_name DailyResultPopup
extends Control
## Yesterday's Daily Run, shown once on Home after the reset when the player
## had a try on it but no prize (a prize shows in DailyPrizePopup instead): the
## day, the player's place, the first three on a podium and Watch for the winner's run,
## whose replay is open now. A flat paper card over the dimmed room; the close
## button in its top right.

signal closed
## Watch the winner's run (LeaderboardBoard.Entry.run_id).
signal watch_requested(run_id: int)

const SIDE := 28
const HEADLINE_SIZE := 64

var _past: DailyRunInfo.Yesterday
var _rank := Label.new()
var _line := Label.new()
var _podium: Podium
var _watch: Button


func _init(past: DailyRunInfo.Yesterday) -> void:
	_past = past
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)
	var day := UiKit.label(day_line(past), &"MutedLabel", false)
	col.add_child(UiKit.card_head(day, closed.emit))
	_rank.theme_type_variation = &"NameLabel"
	_rank.text = "#%d" % past.rank
	_rank.add_theme_font_size_override("font_size", HEADLINE_SIZE)
	_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_rank)
	_line.theme_type_variation = &"InkLabel"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(200, 0)
	_line.text = summary(past)
	col.add_child(_line)
	# The first three on the same podium as the boards, with their prizes.
	_podium = Podium.new(past.top, true, LeaderboardService.DAILY_RUN, true)
	col.add_child(_podium)
	var leader := winner(past)
	if leader != null:
		_watch = UiKit.action_button("Watch %s's run" % leader.player_name)
		_watch.pressed.connect(watch_requested.emit.bind(leader.run_id))
		col.add_child(_watch)


## "Daily Run No. 46, 12 November".
static func day_line(past: DailyRunInfo.Yesterday) -> String:
	var date := DailyPrizePopup.date_text(past.day)
	var board := "Daily Run No. %d" % past.number
	return board if date.is_empty() else "%s, %s" % [board, date]


## "Of 1,980 players, with 44 points. Top 10 win diamonds."
static func summary(past: DailyRunInfo.Yesterday) -> String:
	var of := DailyRunRules.thousands(maxi(past.players, past.rank))
	return "Of %s players, with %d points. Top 10 win diamonds." % [of, past.score]


## The first place, when their replay can be watched.
static func winner(past: DailyRunInfo.Yesterday) -> LeaderboardBoard.Entry:
	if past.top.is_empty() or past.top[0].run_id <= 0:
		return null
	return past.top[0]


func rank_text() -> String:
	return _rank.text


func podium() -> Podium:
	return _podium


func watch_button() -> Button:
	return _watch
