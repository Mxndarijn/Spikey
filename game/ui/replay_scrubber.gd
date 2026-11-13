class_name ReplayScrubber
extends Control
## The replay's timeline (design A3 + P1a, docs/mockups: the replay scrubber
## review page): an ink band under the room with a strip of chapter chips (one
## per room: its Rooms-screen picture, number, name and the fork exit taken)
## and a track split by room, ending in a skull at the crash. Paused, a slim
## control pill floats above the floor spikes: speed, one bounce back, Play,
## one bounce forward and Crash -3 s. Drag the track or tap a chip to jump;
## tap the room to pause or play on. It only asks: main seeks the run
## (ReplayIndex.seek, RunController.seek) and pauses it.

signal seek_requested(tick: int)
signal paused_changed(paused: bool)
signal speed_changed(speed_q: int)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const PAUSE_ICON := preload("res://assets/ui/icons/pause.svg")
const BACK_ICON := preload("res://assets/ui/icons/step_back.svg")
const FORWARD_ICON := preload("res://assets/ui/icons/step_forward.svg")
const SKULL_ICON := preload("res://assets/ui/icons/skull.svg")
const FORK_ICON := preload("res://assets/ui/icons/fork.svg")
const CROWN_ICON := preload("res://assets/ui/icons/crown.svg")

## The band's height; it sits under the room when the phone has that much
## room below it, else over the room's bottom (16:9 phones).
const BAND_H := 56.0
const CHIP_H := 26.0
const CHIP_GAP := 6.0
## Chips and every pill control are at least this tall to tap.
const TAP := float(UiTokens.SIZE_TAP_MIN)
const TRACK_X := 16.0
const TRACK_W := 304.0
## The track's centre below the band's top.
const TRACK_Y := 44.0
## The track's touch area reaches this far above its line.
const TRACK_PAD := 5.0
const SKULL_D := 20.0
const THUMB_D := 18.0
const THUMB_DRAG_D := 26.0
## The pill's bottom edge in the room: 12 px above the floor spike tips (the
## floor row is drawn 28 px tall at the room's bottom).
const PILL_BOTTOM := 600.0
const PILL_H := 44.0
const PILL_FILL := Color(UiTokens.INK_900, 0.82)
## Seconds the pill stays after a drag that started while playing.
const DRAG_LINGER := 2.0
## Speed steps, in quarters (RunController.speed_q), in tap order.
const SPEEDS: Array[int] = [4, 8, 1, 2]
## Crash -3 s jumps this many ticks before the crash.
const CRASH_LEAD := 3 * SimConfig.TICKS_PER_SECOND

var reduced_motion := false

var _index: ReplayIndex
var _run: RunController
var _band_top := ScreenLayout.ROOM.y
var _band_h := BAND_H
var _paused := false
var _dragging := false
var _drag_was_playing := false
var _drag_tick := -1
var _linger := 0.0
var _chip_count := 0
var _chips: Array[Button] = []
var _strip := Control.new()
var _row := HBoxContainer.new()
var _track := Control.new()
var _pill := Control.new()
var _speed: Button
var _back: Button
var _play: Button
var _play_icon := TextureRect.new()
var _forward: Button
var _crash: Button
var _bubble := PanelContainer.new()
var _bubble_text := Label.new()
var _pill_tween: Tween


func _init() -> void:
	name = "ReplayScrubber"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(CHIP_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_row)
	add_child(_strip)
	_track.name = "Track"
	_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_track.gui_input.connect(_on_track_input)
	_track.draw.connect(_draw_track)
	add_child(_track)
	_build_pill()
	_build_bubble()
	_layout()


## The run to scrub: its index and the controller that plays it.
func bind(index: ReplayIndex, run: RunController) -> void:
	_index = index
	_run = run
	_paused = false
	_dragging = false
	_linger = 0.0
	_clear_chips()
	_show_pill(false, true)
	_bubble.visible = false
	if _run != null:
		_run.speed_q = 4
	_refresh_speed()
	visible = index != null


func unbind() -> void:
	bind(null, null)


## Room below the room rect, down to the bottom of the safe area (canvas px).
func set_band_space(space: float) -> void:
	if space >= BAND_H:
		_band_top = ScreenLayout.ROOM.y
		_band_h = space
	else:
		_band_top = ScreenLayout.ROOM.y - BAND_H
		_band_h = BAND_H + maxf(0.0, space)
	_layout()


func is_paused() -> bool:
	return _paused


func is_pill_shown() -> bool:
	return _pill.visible and _pill.modulate.a > 0.0


## Pause or play on (a tap on the room, or the pill's Play).
func toggle_pause() -> void:
	set_paused(not _paused)


func set_paused(value: bool) -> void:
	if _index == null:
		return
	_paused = value
	_linger = 0.0
	_play_icon.texture = PLAY_ICON if value else PAUSE_ICON
	_play.tooltip_text = "Play" if value else "Pause"
	_show_pill(value)
	paused_changed.emit(value)


## Asks main to jump to `tick` (clamped to the timeline).
func jump(tick: int) -> void:
	if _index == null:
		return
	seek_requested.emit(clampi(tick, 0, _last_tick()))


## The tick the scrubber shows: the drag's while dragging, else the run's.
func shown_tick() -> int:
	if _dragging and _drag_tick >= 0:
		return _drag_tick
	return _run.sim.state.tick if _run != null and _run.sim != null else 0


## The screen-x of `tick` on the track (scrubber-local).
func tick_x(tick: int) -> float:
	return TRACK_X + TRACK_W * clampf(float(tick) / _length(), 0.0, 1.0)


## The tick under the scrubber-local x.
func x_tick(x: float) -> int:
	return roundi(clampf((x - TRACK_X) / TRACK_W, 0.0, 1.0) * _length())


func chip_buttons() -> Array[Button]:
	return _chips


func pill_buttons() -> Array[Button]:
	return [_speed, _back, _play, _forward, _crash]


func band_rect() -> Rect2:
	return Rect2(
		Vector2(-ScreenLayout.ROOM.x, _band_top), Vector2(ScreenLayout.ROOM.x * 3.0, _band_h)
	)


## Where the pill rests (it rises 12 px into place when it shows).
func pill_rect() -> Rect2:
	return Rect2(Vector2(_pill.position.x, PILL_BOTTOM - PILL_H), _pill.size)


func _process(delta: float) -> void:
	if _index == null or _run == null or _run.sim == null:
		return
	if _index.room_starts.size() != _chip_count:
		_rebuild_chips()
	if _linger > 0.0:
		_linger -= delta
		if _linger <= 0.0 and not _paused:
			_show_pill(false)
	_place_strip()
	_place_bubble()
	_track.queue_redraw()
	queue_redraw()


## A tap on the room (not on a control) pauses the replay or plays it on.
func _unhandled_input(event: InputEvent) -> void:
	if _index == null or _run == null or _run.sim == null or not is_visible_in_tree():
		return
	if TapInput.is_tap(event) and not _run.sim.is_over():
		get_viewport().set_input_as_handled()
		toggle_pause()


func _draw() -> void:
	# The band is the scrubber's own: ink in every world (the room's own
	# fill below the floor is the world's spike colour, light in some worlds).
	draw_rect(band_rect(), UiTokens.INK_900)


func _layout() -> void:
	_strip.position = Vector2(0, _band_top + 4.0 - (TAP - CHIP_H) / 2.0)
	_strip.size = Vector2(ScreenLayout.ROOM.x, TAP)
	# The track's touch area starts just above it, under the chips' tap areas.
	_track.position = Vector2(0, _band_top + TRACK_Y - TRACK_PAD)
	_track.size = Vector2(ScreenLayout.ROOM.x, maxf(24.0, _band_h - TRACK_Y + TRACK_PAD))
	var w := 0.0
	for b in pill_buttons():
		w += b.custom_minimum_size.x
	_pill.size = Vector2(w + 8.0, PILL_H)
	_pill.position = Vector2((ScreenLayout.ROOM.x - _pill.size.x) / 2.0, PILL_BOTTOM - PILL_H)
	queue_redraw()


func _length() -> float:
	return float(_index.length()) if _index != null else 1.0


func _last_tick() -> int:
	return maxi(0, mini(_index.length(), _index.built_to()) - 1)


# --- the chapter strip -------------------------------------------------------


func _clear_chips() -> void:
	for c in _row.get_children():
		c.queue_free()
	_chips.clear()
	_chip_count = 0


func _rebuild_chips() -> void:
	for k in range(_chip_count, _index.room_starts.size()):
		var chip := _make_chip(k)
		_row.add_child(chip)
		_chips.append(chip)
	_chip_count = _index.room_starts.size()


func _make_chip(k: int) -> Button:
	var def: RoomDef = RoomCatalog.all()[_index.room_kinds[k]]
	var b := Button.new()
	b.name = "Chapter%d" % (k + 1)
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.tooltip_text = "Jump to %d, %s" % [k + 1, RoomInfo.name_of(def.id)]
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, TAP)
	b.pressed.connect(func() -> void: _on_chip(k))
	var face := PanelContainer.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiTheme.flat(UiTokens.ON_SCRIM, UiTokens.RADIUS_PILL, 0)
	box.content_margin_left = 8
	box.content_margin_right = 10
	face.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := RoomThumb.new()
	pic.world = RoomInfo.preview_world(def.id)
	pic.glyph = RoomInfo.glyph(def.id)
	pic.radius = 3.0
	pic.custom_minimum_size = Vector2(14, 15)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var num := _chip_label(str(k + 1))
	num.name = "Number"
	row.add_child(num)
	var title := _chip_label(RoomInfo.name_of(def.id))
	title.name = "Name"
	row.add_child(title)
	var route := _index.room_routes[k]
	if def.boss or route != SimState.ExitKind.NORMAL:
		var tag := TextureRect.new()
		tag.name = "Boss" if def.boss else "Fork"
		tag.texture = CROWN_ICON if def.boss else FORK_ICON
		tag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tag.custom_minimum_size = Vector2(14, 14)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.self_modulate = _route_color(route) if not def.boss else UiTokens.ACTION
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tag)
	face.add_child(row)
	b.add_child(face)
	face.custom_minimum_size = Vector2(0, CHIP_H)
	face.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	face.anchor_top = 0.5
	face.anchor_bottom = 0.5
	face.offset_top = -CHIP_H / 2.0
	face.offset_bottom = CHIP_H / 2.0
	return b


func _chip_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"OnInkLabel"
	l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _route_color(route: int) -> Color:
	match route:
		SimState.ExitKind.CALM:
			return UiTokens.SUCCESS
		SimState.ExitKind.WILD:
			return UiTokens.ACTION
	return UiTokens.ON_SCRIM


func _on_chip(k: int) -> void:
	if not _paused:
		set_paused(true)
	jump(_index.room_starts[k])


## Centres the room shown on the strip, and colours the chips: the current
## one white with ink text, played ones brighter than the ones to come.
func _place_strip() -> void:
	if _chips.is_empty():
		return
	var cur := _index.chapter_at(shown_tick())
	# Chip widths follow their text (known once they're in the tree).
	for chip in _chips:
		var need := (chip.get_node("Face") as Control).get_combined_minimum_size().x
		if not is_equal_approx(chip.custom_minimum_size.x, need):
			chip.custom_minimum_size.x = need
			chip.size.x = need
	var x := 0.0
	for k in _chips.size():
		if k == cur:
			x += _chips[k].size.x / 2.0
			break
		x += _chips[k].size.x + CHIP_GAP
	_row.position = Vector2(ScreenLayout.ROOM.x / 2.0 - x, 0)
	_row.size = Vector2(_row.get_combined_minimum_size().x, TAP)
	for k in _chips.size():
		var face := _chips[k].get_node("Face") as PanelContainer
		var box := face.get_theme_stylebox("panel") as StyleBoxFlat
		var on := k == cur
		box.bg_color = (
			UiTokens.ON_SCRIM if on else Color(UiTokens.ON_SCRIM, 0.22 if k < cur else 0.12)
		)
		var ink := UiTokens.INK_LINE if on else Color(UiTokens.ON_SCRIM, 0.9)
		for n in ["Name", "Number"]:
			var l := face.get_node("Row/" + n) as Label
			if l != null:
				l.add_theme_color_override("font_color", ink)


# --- the track ---------------------------------------------------------------


func _draw_track() -> void:
	if _index == null:
		return
	var cy := TRACK_PAD
	var h := 6.0 if _paused or _dragging else 4.0
	var tick := shown_tick()
	var built := float(_index.built_to())
	for k in _index.room_starts.size():
		var a := tick_x(_index.room_starts[k]) + (1.0 if k > 0 else 0.0)
		var end_tick := (
			_index.room_starts[k + 1]
			if k + 1 < _index.room_starts.size()
			else int(minf(built, _length()))
		)
		var b := tick_x(end_tick) - (1.0 if k + 1 < _index.room_starts.size() else 0.0)
		if b <= a:
			continue
		var route := _index.room_routes[k]
		var lit := _route_color(route)
		var dim := Color(lit, 0.5 if route != SimState.ExitKind.NORMAL else 0.26)
		_pill_bar(Rect2(a, cy - h / 2.0, b - a, h), dim)
		var played := clampf(tick_x(tick), a, b)
		if played > a:
			_pill_bar(Rect2(a, cy - h / 2.0, played - a, h), lit)
	# Not played by the index yet: a faint bar to the end.
	if built < _length():
		var a2 := tick_x(int(built)) + 1.0
		_pill_bar(Rect2(a2, cy - h / 2.0, TRACK_X + TRACK_W - a2, h), Color(UiTokens.ON_SCRIM, 0.1))
	for c in _index.coins:
		_track.draw_rect(Rect2(tick_x(c) - 1.0, cy - 1.0, 2.0, 2.0), UiTokens.COIN)
	for r in _index.revived_at:
		_track.draw_arc(Vector2(tick_x(r), cy), 5.0, 0.0, TAU, 16, UiTokens.ON_SCRIM, 1.5, true)
	var skull := Vector2(TRACK_X + TRACK_W + 4.0 + SKULL_D / 2.0, cy)
	_track.draw_circle(skull, SKULL_D / 2.0, UiTokens.ON_SCRIM)
	var s := Vector2(14, 14)
	_track.draw_texture_rect(SKULL_ICON, Rect2(skull - s / 2.0, s), false, UiTokens.INK_LINE)
	if _paused or _dragging:
		var d := THUMB_DRAG_D if _dragging else THUMB_D
		var at := Vector2(tick_x(tick), cy)
		_track.draw_circle(at, d / 2.0, UiTokens.ON_SCRIM)
		_track.draw_circle(at, 3.5, UiTokens.INK_LINE)


func _pill_bar(r: Rect2, col: Color) -> void:
	var rad := r.size.y / 2.0
	if r.size.x <= r.size.y:
		_track.draw_circle(r.get_center(), minf(rad, r.size.x / 2.0), col)
		return
	_track.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	_track.draw_circle(Vector2(r.position.x + rad, r.get_center().y), rad, col)
	_track.draw_circle(Vector2(r.end.x - rad, r.get_center().y), rad, col)


func _on_track_input(event: InputEvent) -> void:
	if _index == null:
		return
	var press := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventMouseMotion
	var sdrag := event as InputEventScreenDrag
	if (press != null and press.button_index == MOUSE_BUTTON_LEFT) or touch != null:
		var down := press.pressed if press != null else touch.pressed
		var x := press.position.x if press != null else touch.position.x
		if down and not _dragging:
			_begin_drag(x)
		elif not down and _dragging:
			_end_drag()
		accept_event()
	elif _dragging and (drag != null or sdrag != null):
		_drag_to(drag.position.x if drag != null else sdrag.position.x)
		accept_event()


func _begin_drag(x: float) -> void:
	_dragging = true
	_drag_was_playing = not _paused
	if not _paused:
		_paused = true
		paused_changed.emit(true)
	_show_pill(true)
	_bubble.visible = true
	_drag_to(x)


func _drag_to(x: float) -> void:
	var t := clampi(x_tick(x), 0, _last_tick())
	if t == _drag_tick:
		return
	_drag_tick = t
	jump(t)


func _end_drag() -> void:
	_dragging = false
	_drag_tick = -1
	_bubble.visible = false
	if _drag_was_playing:
		_paused = false
		paused_changed.emit(false)
		_linger = DRAG_LINGER
	_play_icon.texture = PLAY_ICON if _paused else PAUSE_ICON


# --- the pill ----------------------------------------------------------------


func _build_pill() -> void:
	_pill.name = "Controls"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UiTheme.flat(PILL_FILL, UiTokens.RADIUS_PILL, 0))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pill.add_child(bg)
	_speed = _pill_button("Speed", null, "1×", 52.0, "Replay speed")
	_speed.pressed.connect(_cycle_speed)
	_back = _pill_button("BounceBack", BACK_ICON, "", TAP, "One bounce back")
	_back.pressed.connect(func() -> void: _step(-1))
	_play = _pill_button("Play", null, "", TAP, "Play")
	_play.pressed.connect(toggle_pause)
	# Play is the one white disc (40 px, inside its 44 px tap area).
	var disc := Panel.new()
	disc.name = "Disc"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.show_behind_parent = true
	disc.add_theme_stylebox_override(
		"panel", UiTheme.flat(UiTokens.ON_SCRIM, UiTokens.RADIUS_PILL, 0)
	)
	disc.set_anchors_preset(Control.PRESET_CENTER)
	disc.offset_left = -20.0
	disc.offset_top = -20.0
	disc.offset_right = 20.0
	disc.offset_bottom = 20.0
	_play_icon.texture = PLAY_ICON
	_play_icon.modulate = UiTokens.INK_LINE
	_play_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_play_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_play_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play_icon.offset_left = 10.0
	_play_icon.offset_top = 10.0
	_play_icon.offset_right = -10.0
	_play_icon.offset_bottom = -10.0
	disc.add_child(_play_icon)
	_play.add_child(disc)
	_play.add_theme_color_override("icon_normal_color", UiTokens.INK_LINE)
	_play.add_theme_color_override("icon_hover_color", UiTokens.INK_LINE)
	_play.add_theme_color_override("icon_pressed_color", UiTokens.INK_LINE)
	_forward = _pill_button("BounceForward", FORWARD_ICON, "", TAP, "One bounce forward")
	_forward.pressed.connect(func() -> void: _step(1))
	_crash = _pill_button("CrashJump", SKULL_ICON, "−3 s", 64.0, "Jump to 3 s before the crash")
	_crash.pressed.connect(_jump_to_crash)
	_crash.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_crash.add_theme_constant_override("icon_max_width", 16)
	var x := 4.0
	for b in pill_buttons():
		b.position = Vector2(x, 0)
		b.size = Vector2(b.custom_minimum_size.x, PILL_H)
		_pill.add_child(b)
		x += b.custom_minimum_size.x
	_pill.visible = false
	add_child(_pill)


func _pill_button(id: String, icon: Texture2D, text: String, w: float, tip: String) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.icon = icon
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.custom_minimum_size = Vector2(w, TAP)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 20)
	b.add_theme_constant_override("h_separation", 3)
	b.add_theme_font_override("font", GameFonts.ui(800))
	b.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL - 1)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "icon_normal_color"]:
		b.add_theme_color_override(c, UiTokens.ON_SCRIM)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return b


func _show_pill(on: bool, instant: bool = false) -> void:
	if _pill_tween != null:
		_pill_tween.kill()
		_pill_tween = null
	var rest := PILL_BOTTOM - PILL_H
	if instant or not is_inside_tree():
		_pill.visible = on
		_pill.modulate.a = 1.0 if on else 0.0
		_pill.position.y = rest
		return
	var move := 0.0 if reduced_motion else 1.0
	_pill_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if on:
		_pill.visible = true
		_pill.modulate.a = 0.0
		_pill.position.y = rest + 12.0 * move
		_pill_tween.parallel().tween_property(_pill, "modulate:a", 1.0, 0.16)
		_pill_tween.parallel().tween_property(_pill, "position:y", rest, 0.16)
	else:
		_pill_tween.parallel().tween_property(_pill, "modulate:a", 0.0, 0.12)
		_pill_tween.parallel().tween_property(_pill, "position:y", rest + 8.0 * move, 0.12)
		_pill_tween.tween_callback(func() -> void: _pill.visible = false)


func _cycle_speed() -> void:
	if _run == null:
		return
	var i := SPEEDS.find(_run.speed_q)
	_run.speed_q = SPEEDS[(i + 1) % SPEEDS.size()]
	_refresh_speed()
	speed_changed.emit(_run.speed_q)


func _refresh_speed() -> void:
	var q := _run.speed_q if _run != null else 4
	match q:
		1:
			_speed.text = "0.25×"
		2:
			_speed.text = "0.5×"
		8:
			_speed.text = "2×"
		_:
			_speed.text = "1×"


func _step(dir: int) -> void:
	if _index == null:
		return
	if not _paused:
		set_paused(true)
	var now := shown_tick()
	var to := _index.bounce_before(now) if dir < 0 else _index.bounce_after(now)
	if to >= 0:
		jump(to)


func _jump_to_crash() -> void:
	if _index == null:
		return
	if not _paused:
		set_paused(true)
	jump(_index.length() - CRASH_LEAD)


# --- the drag bubble ---------------------------------------------------------


func _build_bubble() -> void:
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiTheme.flat(UiTokens.INK_LINE, 14, 0)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	_bubble.add_theme_stylebox_override("panel", box)
	_bubble_text.theme_type_variation = &"OnInkLabel"
	_bubble_text.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_bubble_text)
	_bubble.visible = false
	add_child(_bubble)


func _place_bubble() -> void:
	if not _bubble.visible or _run == null or _run.sim == null:
		return
	_bubble_text.text = "%s · %d" % [clock(shown_tick(), true), _run.sim.shown_score()]
	var w := _bubble.get_combined_minimum_size()
	_bubble.size = w
	var x := clampf(tick_x(shown_tick()) - w.x / 2.0, 12.0, ScreenLayout.ROOM.x - 12.0 - w.x)
	_bubble.position = Vector2(x, _band_top - w.y - 8.0)


## "1:12.4" (with tenths) or "1:12" for `tick`.
static func clock(tick: int, tenths: bool = false) -> String:
	var tenth := tick * 10 / SimConfig.TICKS_PER_SECOND
	var secs := tenth / 10
	var text := "%d:%02d" % [secs / 60, secs % 60]
	return text + (".%d" % (tenth % 10) if tenths else "")
