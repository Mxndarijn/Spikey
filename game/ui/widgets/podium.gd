class_name Podium
extends HBoxContainer
## The top 3 of a board on gold, silver and bronze blocks: second, first,
## third from left to right. Each stands with its flyer, a medal with the place,
## a name tag with the verified shield, and the score on the block.
## An empty board shows three blocks with a "?" waiting for players.

const GOLD := Color("#FFC21A")
const SILVER := Color("#DCDFEA")
const BRONZE := Color("#F2A65A")
## Per place: block colour, block height, score size, flyer size.
const LOOK := {
	1: [GOLD, 36.0, 22, 46.0],
	2: [SILVER, 30.0, 19, 38.0],
	3: [BRONZE, 26.0, 18, 38.0],
}
const TAG_TEXT_MAX := 66.0
const MEDAL := 22.0

var _spots := []


func _init(entries: Array[LeaderboardBoard.Entry]) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	for place in [2, 1, 3]:
		var e: LeaderboardBoard.Entry = entries[place - 1] if entries.size() >= place else null
		add_child(_column(place, e))
		_spots.append(e)


func _column(place: int, e: LeaderboardBoard.Entry) -> Control:
	var look: Array = LOOK[place]
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_theme_constant_override("separation", 2)
	if e != null:
		var holder := _flyer(e, look[3], place, look[0])
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(holder)
		var tag := _tag(e)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(tag)
	else:
		var waiting := _waiting()
		waiting.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(waiting)
	col.add_child(_block(look, str(e.score) if e != null else str(place)))
	return col


func _flyer(e: LeaderboardBoard.Entry, side: float, place: int, color: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(side, side)
	var pic := LeaderboardRow.icon(LeaderboardRow.flyer_texture(e.flyer_id), side)
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pic)
	var medal := PanelContainer.new()
	var disc := StyleBoxFlat.new()
	disc.bg_color = color
	disc.set_corner_radius_all(UiTokens.RADIUS_PILL)
	disc.set_border_width_all(2)
	disc.border_color = UiTokens.INK_LINE
	disc.anti_aliasing = true
	medal.add_theme_stylebox_override("panel", disc)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.custom_minimum_size = Vector2(MEDAL, MEDAL)
	medal.position = Vector2(-9, -4)
	medal.size = Vector2(MEDAL, MEDAL)
	var n := Label.new()
	n.theme_type_variation = &"InkLabel"
	n.add_theme_font_size_override("font_size", 13)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.text = str(place)
	medal.add_child(n)
	holder.add_child(medal)
	return holder


func _tag(e: LeaderboardBoard.Entry) -> Control:
	var tag := PanelContainer.new()
	var fill := UiTheme.SELECTED_FILL if e.is_me else UiTokens.PANEL
	var box := UiTheme.sticker(fill, UiTokens.RADIUS_PILL, Vector2.ZERO, 1, 2)
	box.content_margin_left = 7
	box.content_margin_right = 6
	tag.add_theme_stylebox_override("panel", box)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.theme_type_variation = &"StatusLabel"
	l.text = e.player_name
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var wide := GameFonts.ui(800).get_string_size(
		e.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.FONT_SIZE_CAPTION
	)
	l.custom_minimum_size = Vector2(minf(ceilf(wide.x) + 1.0, TAG_TEXT_MAX), 0)
	row.add_child(l)
	if e.verified:
		row.add_child(LeaderboardRow.icon(LeaderboardRow.VERIFIED_ICON, 13))
	tag.add_child(row)
	return tag


## A white ring with a "?" where a player will stand.
func _waiting() -> Control:
	var ring := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTokens.PANEL, 0.0)
	box.set_border_width_all(3)
	box.border_color = UiTokens.ON_SKY
	box.set_corner_radius_all(UiTokens.RADIUS_PILL)
	box.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", box)
	ring.custom_minimum_size = Vector2(40, 40)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var q := Label.new()
	q.theme_type_variation = &"SkyLabel"
	q.add_theme_font_size_override("font_size", 20)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.text = "?"
	ring.add_child(q)
	return ring


func _block(look: Array, text: String) -> Control:
	var block := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = look[0]
	box.border_width_left = UiTheme.BORDER
	box.border_width_top = UiTheme.BORDER
	box.border_width_right = UiTheme.BORDER
	box.border_color = UiTokens.INK_LINE
	box.corner_radius_top_left = 12
	box.corner_radius_top_right = 12
	box.content_margin_top = 2
	box.anti_aliasing = true
	block.add_theme_stylebox_override("panel", box)
	block.custom_minimum_size = Vector2(0, look[1])
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", look[2])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.text = text
	block.add_child(l)
	return block


## Who stands on 2nd, 1st and 3rd (null where nobody does yet), for tests.
func spots() -> Array:
	return _spots
