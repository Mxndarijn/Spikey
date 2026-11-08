class_name LeaderboardRow
extends PanelContainer
## One leaderboard row (Sticker Pop): rank, flyer, name, the mint "verified"
## shield and the score. The player's own row is cream.

const VERIFIED_ICON := preload("res://assets/ui/icons/verified.svg")
const HEIGHT := 44.0
const RANK_WIDTH := 26.0
const FLYER := 32.0
const LINE := Color("#ECE8F4")

var entry: LeaderboardBoard.Entry


func _init(e: LeaderboardBoard.Entry) -> void:
	entry = e
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.SELECTED_FILL if e.is_me else Color(UiTokens.PANEL, 0.0)
	box.border_width_bottom = 2
	box.border_color = LINE
	box.content_margin_left = UiTokens.SPACE_2
	box.content_margin_right = 10
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	add_child(row)
	var rank := Label.new()
	rank.theme_type_variation = &"InkLabel"
	rank.add_theme_font_size_override("font_size", 16)
	rank.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	rank.custom_minimum_size = Vector2(RANK_WIDTH, 0)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank.text = str(e.rank)
	row.add_child(rank)
	row.add_child(icon(flyer_texture(e.flyer_id), FLYER))
	var name_label := Label.new()
	name_label.theme_type_variation = &"StatusLabel"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.text = e.player_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.custom_minimum_size = Vector2(40, 0)
	row.add_child(name_label)
	if e.verified:
		var mark := icon(VERIFIED_ICON, 14)
		mark.tooltip_text = "Verified by the server"
		row.add_child(mark)
	var score := Label.new()
	score.theme_type_variation = &"CoinLabel"
	score.add_theme_font_size_override("font_size", 20)
	score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score.text = str(e.score)
	row.add_child(score)


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
