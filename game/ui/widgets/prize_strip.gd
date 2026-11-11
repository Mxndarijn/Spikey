class_name PrizeStrip
extends PanelContainer
## What the daily places win, on one paper pill above the podium:
## "1st ◆ 3 | 2nd–3rd ◆ 2 | 4th–10th ◆ 1". Built from Economy.DAILY_PRIZES,
## so the strip always says what the board pays. 1st sits on gold.

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const HEIGHT := 28.0
const TEXT_SIZE := 13


func _init() -> void:
	name = "PrizeStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	box.set_content_margin_all(2)
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	for tier in tiers():
		row.add_child(_segment(tier[0], tier[1], tier[0] == "1st"))


## The places that win the same amount, grouped: [["1st", 3], ["2nd–3rd", 2], ...].
static func tiers() -> Array:
	var out := []
	var prizes := Economy.DAILY_PRIZES
	var start := 0
	for i in prizes.size():
		if i + 1 < prizes.size() and prizes[i + 1] == prizes[i]:
			continue
		var places := SpotAlert.ordinal(start + 1)
		if i > start:
			places += "–" + SpotAlert.ordinal(i + 1)
		out.append([places, prizes[i]])
		start = i + 1
	return out


func _segment(places: String, amount: int, gold: bool) -> Control:
	var seg := PanelContainer.new()
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.add_theme_stylebox_override(
		"panel",
		UiTheme.flat(UiTokens.ACTION if gold else UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, 0)
	)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 3)
	seg.add_child(line)
	line.add_child(_label(places))
	line.add_child(LeaderboardRow.icon(DIAMOND_ICON, 14))
	line.add_child(_label(str(amount)))
	seg.tooltip_text = "%s wins %s" % [places, SpotAlert.diamonds(amount)]
	return seg


func _label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", TEXT_SIZE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	return l


## The segments' words ("1st 3", "2nd–3rd 2", ...), for tests.
func segment_texts() -> Array[String]:
	var out: Array[String] = []
	for seg in (get_child(0) as HBoxContainer).get_children():
		var line := seg.get_child(0) as HBoxContainer
		out.append("%s %s" % [(line.get_child(0) as Label).text, (line.get_child(2) as Label).text])
	return out
