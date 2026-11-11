class_name RunRow
extends PanelContainer
## One run on Your runs (minimal kit): a flat paper card with the score, a dot
## in the world's colour, when it was played (and a gold Best tag), what
## happened ("Sunset, 4 rooms, revived at 12"), the round ink Watch button and
## the bookmark that saves it. A run from an older gameplay version can't be
## watched: its Watch button is off and the line says so.

signal watch_pressed(record: RunRecord)
signal save_pressed(record: RunRecord)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const BOOKMARK_ICON := preload("res://assets/ui/icons/bookmark.svg")
const BOOKMARK_ON_ICON := preload("res://assets/ui/icons/bookmark_on.svg")
const HEIGHT := 56.0
const SCORE_W := 52.0
const DOT := 10.0
const BUTTON := 44.0
const OLD_VERSION := "older version, can't be watched"

var record: RunRecord
var _watch: Button
var _save: Button
var _when: Label
var _detail: Label


func _init(p_record: RunRecord, now: int, bias_minutes: int = 0) -> void:
	record = p_record
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	box.content_margin_left = 14
	box.content_margin_right = 6
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var score := UiKit.label(str(record.score()), &"NameLabel", false)
	score.custom_minimum_size = Vector2(SCORE_W, 0)
	score.add_theme_font_size_override("font_size", 24)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(score)
	row.add_child(_text_column(now, bias_minutes))
	_watch = _round_button(PLAY_ICON, "Watch")
	_watch.name = "Watch"
	_watch.disabled = not record.watchable()
	if _watch.disabled:
		_watch.tooltip_text = "Played in an older version: can't be watched"
	_watch.pressed.connect(func() -> void: watch_pressed.emit(record))
	row.add_child(_watch)
	_save = UiKit.icon_button(BOOKMARK_ICON, "", &"InkButton", BUTTON)
	_save.name = "Save"
	_save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save.pressed.connect(func() -> void: save_pressed.emit(record))
	row.add_child(_save)
	refresh()


func _text_column(now: int, bias_minutes: int) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	top.add_child(_dot(world_color(record.world)))
	_when = UiKit.label(when_text(record.played_at, now, bias_minutes), &"SmallNameLabel", false)
	_when.clip_text = true
	_when.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_when)
	if record.best:
		top.add_child(_best_tag())
	col.add_child(top)
	_detail = UiKit.label(detail_text(record), &"MutedLabel", false)
	_detail.add_theme_font_size_override("font_size", 12)
	_detail.clip_text = true
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_detail)
	return col


static func _dot(color: Color) -> Control:
	var dot := Panel.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UiTheme.flat(color, UiTokens.RADIUS_PILL, 0))
	return dot


static func _best_tag() -> Control:
	var tag := PanelContainer.new()
	tag.name = "Best"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := UiTheme.flat(UiTokens.ACTION, UiTokens.RADIUS_PILL, 0)
	box.content_margin_left = 7
	box.content_margin_right = 7
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	tag.add_theme_stylebox_override("panel", box)
	var l := UiKit.label("Best", &"StatusLabel")
	l.add_theme_font_size_override("font_size", 11)
	tag.add_child(l)
	return tag


## A 44px round ink button with a white icon; off, it fades to the soft edge.
static func _round_button(icon: Texture2D, tip: String) -> Button:
	var b := UiKit.icon_button(icon, tip, &"InkButton", BUTTON)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_constant_override("icon_max_width", 18)
	var on := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0)
	var down := UiTheme.flat(UiTokens.PRIMARY.lightened(0.15), UiTokens.RADIUS_PILL, 0)
	var off := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover"]:
		b.add_theme_stylebox_override(state, on)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	b.add_theme_stylebox_override("disabled", off)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	b.add_theme_color_override("icon_disabled_color", Color(UiTokens.ON_PANEL, 0.45))
	return b


## Shows whether the run is saved (after the bookmark was tapped).
func refresh() -> void:
	_save.icon = BOOKMARK_ON_ICON if record.saved else BOOKMARK_ICON
	_save.tooltip_text = "Saved, tap to remove" if record.saved else "Save this run"


func watch_button() -> Button:
	return _watch


func save_button() -> Button:
	return _save


func when_line() -> String:
	return _when.text


func detail_line() -> String:
	return _detail.text


## "Sunset, 4 rooms, revived at 12"; an older run says it can't be watched.
static func detail_text(r: RunRecord) -> String:
	var parts: Array[String] = [world_name(r.world)]
	parts.append("1 room" if r.rooms == 1 else "%d rooms" % r.rooms)
	if r.revived():
		parts.append("revived at %d" % r.revived_at)
	if not r.watchable():
		parts.append(OLD_VERSION)
	return ", ".join(parts)


static func world_name(id: String) -> String:
	var t := Catalog.world(id)
	if t != null:
		return t.display_name
	return id.capitalize() if not id.is_empty() else "Unknown world"


static func world_color(id: String) -> Color:
	var t := Catalog.world(id)
	return t.world_accent if t != null else UiTokens.EDGE


## When a run was played, from `now` (both unix seconds; `bias_minutes` is the
## local time zone): "Just now", "6 min ago", "Today, 14:02", "Yesterday",
## "3 Nov", or "3 Nov 2025" in another year.
static func when_text(played_at: int, now: int, bias_minutes: int = 0) -> String:
	var ago := now - played_at
	if ago < 60:
		return "Just now"
	if ago < 3600:
		return "%d min ago" % floori(ago / 60.0)
	var offset := bias_minutes * 60
	var day := floori((played_at + offset) / 86400.0)
	var today := floori((now + offset) / 86400.0)
	var t := Time.get_datetime_dict_from_unix_time(played_at + offset)
	if day == today:
		return "Today, %02d:%02d" % [t.hour, t.minute]
	if day == today - 1:
		return "Yesterday"
	var months := [
		"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
	]
	var text := "%d %s" % [t.day, months[int(t.month) - 1]]
	var this_year := int(Time.get_datetime_dict_from_unix_time(now + offset).year)
	if int(t.year) != this_year:
		text += " %d" % t.year
	return text
