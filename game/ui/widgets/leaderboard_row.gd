class_name LeaderboardRow
extends PanelContainer
## One leaderboard row (minimal kit): a flat paper pill with the rank, a small
## flyer, the name and the score. The player's own row is gold. A row with a
## name plate (PlateStyle) shows that plate instead of the paper, with white
## text on a dark one; the player's own then keeps a gold ring round it.

const VERIFIED_ICON := preload("res://assets/ui/icons/verified.svg")
const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
const REVIVE_MARK := 16.0
const HEIGHT := 48.0
const RANK_WIDTH := 34.0
const FLYER := 32.0
const RING := 3.0

var entry: LeaderboardBoard.Entry
## The plate drawn behind the row, or null for the plain row.
var plate: PlateStyle
## Diamonds this place wins on the daily board (0: none, nothing is shown).
var prize := 0


func _init(e: LeaderboardBoard.Entry, p_prize: int = 0) -> void:
	entry = e
	prize = p_prize
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	var style := Catalog.plate(e.plate_id)
	if style != null and not style.is_plain():
		plate = style
	var fill := UiTokens.ACTION if e.is_me else UiTokens.PANEL
	# A plate is drawn in _draw; its box only keeps the row's margins.
	add_theme_stylebox_override("panel", pill(Color.TRANSPARENT if plate != null else fill))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var labels: Array[Label] = [
		rank_label(str(e.rank)), name_label(e.player_name), score_label(e.score)
	]
	row.add_child(labels[0])
	row.add_child(icon(flyer_texture(e.flyer_id), FLYER))
	row.add_child(labels[1])
	if e.revived:
		row.add_child(revive_mark())
	if prize > 0:
		row.add_child(prize_chip(prize))
	row.add_child(labels[2])
	if plate != null:
		for l in labels:
			l.add_theme_color_override("font_color", plate.text_color())


func _draw() -> void:
	if plate == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	PlatePainter.paint(self, rect, plate)
	if entry != null and entry.is_me:
		PlatePainter.ring(self, rect, RING)


## The row's box: a flat pill, a little more room on the score side.
static func pill(fill: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
	box.content_margin_left = 10
	box.content_margin_right = 14
	return box


## The place, 14/800, in a 34px column.
static func rank_label(text: String) -> Label:
	var rank := Label.new()
	rank.theme_type_variation = &"InkLabel"
	rank.add_theme_font_size_override("font_size", 14)
	rank.custom_minimum_size = Vector2(RANK_WIDTH, 0)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank.text = text
	return rank


## The name, 15/800, taking the free width and trimmed when too long.
static func name_label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", 15)
	l.text = text
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size = Vector2(40, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The score in the display font, 18.
static func score_label(score: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"NameLabel"
	l.add_theme_font_size_override("font_size", 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = str(score)
	return l


## "+3 ◆": the diamonds a daily place wins, white on an ink pill (gold with an
## ink ring for 1st). Its own colours, so it reads the same on any name plate.
static func prize_chip(amount: int, gold: bool = false) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Prize"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := UiTheme.flat(UiTokens.ACTION if gold else UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0)
	if gold:
		box.set_border_width_all(2)
		box.border_color = UiTokens.ON_ACTION
	box.content_margin_left = 7
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", box)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 3)
	chip.add_child(line)
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTokens.ON_ACTION if gold else UiTokens.ON_PRIMARY)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = "+%d" % amount
	line.add_child(l)
	line.add_child(icon(DIAMOND_ICON, 14))
	chip.tooltip_text = "Wins %s today" % SpotAlert.diamonds(amount)
	return chip


## The amount on a prize chip ("+3"), for tests; "" without one.
func prize_text() -> String:
	var chip := find_child("Prize", true, false)
	if chip == null:
		return ""
	return ((chip.get_child(0) as HBoxContainer).get_child(0) as Label).text


## The small ink heart next to the score of a run that used its revive.
static func revive_mark(side: float = REVIVE_MARK) -> TextureRect:
	var mark := icon(HEART_ICON, side)
	mark.name = "Revived"
	mark.modulate = UiTokens.ON_PANEL
	mark.tooltip_text = "Used a revive"
	return mark


## A flyer's idle art, or the first flyer's when the id is unknown.
static func flyer_texture(id: String) -> Texture2D:
	var f := Catalog.flyer(id)
	if f == null:
		f = Catalog.flyers()[0]
	return f.idle


## A fixed-size picture that keeps its aspect.
static func icon(tex: Texture2D, side: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
