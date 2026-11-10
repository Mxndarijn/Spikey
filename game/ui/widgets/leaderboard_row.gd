class_name LeaderboardRow
extends PanelContainer
## One leaderboard row (minimal kit): a flat paper pill with the rank, a small
## flyer, the name and the score. The player's own row is gold.

const VERIFIED_ICON := preload("res://assets/ui/icons/verified.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
const REVIVE_MARK := 16.0
const HEIGHT := 48.0
const RANK_WIDTH := 34.0
const FLYER := 32.0

var entry: LeaderboardBoard.Entry


func _init(e: LeaderboardBoard.Entry) -> void:
	entry = e
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", pill(UiTokens.ACTION if e.is_me else UiTokens.PANEL))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	row.add_child(rank_label(str(e.rank)))
	row.add_child(icon(flyer_texture(e.flyer_id), FLYER))
	row.add_child(name_label(e.player_name))
	if e.revived:
		row.add_child(revive_mark())
	row.add_child(score_label(e.score))


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
