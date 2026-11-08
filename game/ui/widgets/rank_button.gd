class_name RankButton
extends Button
## The home screen's Leaderboard button: the Best pill grown into one sticker,
## "Best 87 | trophy Rank #38 >". Your best score and where it stands belong
## together. The rank is today's (the daily board); "#-" until a run counts.

const MEDAL := preload("res://assets/ui/medal.svg")
const TROPHY := preload("res://assets/ui/icons/trophy.svg")
const CHEVRON := preload("res://assets/ui/icons/chevron.svg")
const HEIGHT := 46.0
## Drops straight down like the other buttons, so it reads as pressable.
const DROP := Vector2(0, 4)

var _row := HBoxContainer.new()
var _best := Label.new()
var _rank := Label.new()


func _init(best: int, rank: int) -> void:
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Leaderboards"
	var box := UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, DROP, 0)
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box.pressed())
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 5)
	add_child(_row)
	if best > 0:
		_row.add_child(LeaderboardRow.icon(MEDAL, 28))
		_row.add_child(_stack("Best", _best))
		_best.text = str(best)
		var line := ColorRect.new()
		line.color = UiTokens.INK_LINE
		line.custom_minimum_size = Vector2(3, 26)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gap := MarginContainer.new()
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.add_theme_constant_override("margin_left", 4)
		gap.add_theme_constant_override("margin_right", 4)
		gap.add_child(line)
		_row.add_child(gap)
	_row.add_child(LeaderboardRow.icon(TROPHY, 24))
	_row.add_child(_stack("Rank", _rank))
	var chevron := LeaderboardRow.icon(CHEVRON, 14)
	chevron.modulate = UiTokens.INK_LINE
	_row.add_child(chevron)
	set_rank(rank)


func _stack(word: String, value: Label) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", -6)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var w := Label.new()
	w.theme_type_variation = &"MutedLabel"
	w.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	w.text = word
	col.add_child(w)
	value.theme_type_variation = &"CoinLabel"
	value.add_theme_font_size_override("font_size", 18)
	col.add_child(value)
	return col


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_row.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _row.get_combined_minimum_size()
	custom_minimum_size = Vector2(content.x + 14, maxf(content.y, HEIGHT))
	_row.offset_left = 4
	_row.offset_right = -10


## Today's rank, 0 for none yet.
func set_rank(rank: int) -> void:
	_rank.text = "#%d" % rank if rank > 0 else "#–"
	tooltip_text = "Leaderboards, %s today" % _rank.text if rank > 0 else "Leaderboards"


func rank_text() -> String:
	return _rank.text


func best_text() -> String:
	return _best.text
