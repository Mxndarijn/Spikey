class_name Podium
extends HBoxContainer
## The top 3 of a board (minimal kit): second, first, third from left to right.
## Each spot is the flyer on the room, the name, and a flat paper block (round
## top corners) with a medal disc holding the place and the score. First
## stands tallest. An empty board shows "?" where players will stand.

const GOLD := Color("#FFC93C")
const SILVER := Color("#D9DDE8")
const BRONZE := Color("#E9B58A")
## Per place: medal colour, block height. The 3rd block grows a little past
## the design's 48px to hold its medal and score.
const LOOK := {
	1: [GOLD, 86.0],
	2: [SILVER, 62.0],
	3: [BRONZE, 48.0],
}
const SPOT_WIDTH := 88.0
const FLYER_BODY := 36.0
const MEDAL := 28.0
const SCORE_SIZE := 20
const NAME_SIZE := 13

var _spots := []


func _init(entries: Array[LeaderboardBoard.Entry]) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)
	for place in [2, 1, 3]:
		var e: LeaderboardBoard.Entry = entries[place - 1] if entries.size() >= place else null
		add_child(_column(place, e))
		_spots.append(e)


func _column(place: int, e: LeaderboardBoard.Entry) -> Control:
	var look: Array = LOOK[place]
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(SPOT_WIDTH, 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_theme_constant_override("separation", 4)
	if e != null:
		col.add_child(_flyer(e))
		col.add_child(_name(e.player_name))
	else:
		col.add_child(_waiting())
	var revived := e != null and e.revived
	col.add_child(_block(look, str(e.score) if e != null else "", place, revived))
	return col


## The flyer standing on the room, still (no bob, no trail).
func _flyer(e: LeaderboardBoard.Entry) -> Control:
	var art := FlyerArt.new(LeaderboardRow.flyer_texture(e.flyer_id), FLYER_BODY)
	art.bob = false
	art.trail_dots = 0
	art.custom_minimum_size = Vector2(SPOT_WIDTH, FLYER_BODY * 1.3)
	return art


func _name(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"SkyCaption"
	l.add_theme_font_size_override("font_size", NAME_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(SPOT_WIDTH, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A soft paper disc with a "?" where a player will stand.
func _waiting() -> Control:
	var ring := PanelContainer.new()
	ring.add_theme_stylebox_override(
		"panel", UiTheme.flat(Color(UiTokens.PANEL, 0.55), UiTokens.RADIUS_PILL, 0)
	)
	ring.custom_minimum_size = Vector2(44, 44)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var q := Label.new()
	q.theme_type_variation = &"NameLabel"
	q.add_theme_font_size_override("font_size", 20)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.text = "?"
	ring.add_child(q)
	return ring


## The paper block: round top corners, the medal with the place, the score
## (with the small heart of a revived run).
func _block(look: Array, score: String, place: int, revived: bool = false) -> Control:
	var block := PanelContainer.new()
	var box := UiTheme.flat(UiTokens.PANEL, 0, 0)
	box.corner_radius_top_left = 16
	box.corner_radius_top_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 2
	block.add_theme_stylebox_override("panel", box)
	block.custom_minimum_size = Vector2(SPOT_WIDTH, look[1])
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 0)
	block.add_child(col)
	col.add_child(_medal(look[0], place))
	if not score.is_empty():
		var l := Label.new()
		l.theme_type_variation = &"NameLabel"
		l.add_theme_font_size_override("font_size", SCORE_SIZE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = score
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 3)
		if revived:
			line.add_child(LeaderboardRow.revive_mark(12.0))
		line.add_child(l)
		col.add_child(line)
	return block


func _medal(color: Color, place: int) -> Control:
	var medal := PanelContainer.new()
	medal.add_theme_stylebox_override("panel", UiTheme.flat(color, UiTokens.RADIUS_PILL, 0))
	medal.custom_minimum_size = Vector2(MEDAL, MEDAL)
	medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Label.new()
	n.theme_type_variation = &"InkLabel"
	n.add_theme_font_override("font", GameFonts.ui(900))
	n.add_theme_font_size_override("font_size", 14)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.text = str(place)
	medal.add_child(n)
	return medal


## Who stands on 2nd, 1st and 3rd (null where nobody does yet), for tests.
func spots() -> Array:
	return _spots
