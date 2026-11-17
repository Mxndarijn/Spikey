class_name LayoutQa
extends RefCounted
## Layout checks for a menu screen laid out in the room (360 x 640), used by
## tests/unit/test_layout_qa.gd. Returns a list of problems, empty when the
## screen is clean:
##   - "outside": a visible element reaches past the room's sides or into the
##     ceiling or floor spike rows (above SimConfig.KILL_TOP, or within CLEAR px
##     of KILL_BOTTOM).
##   - "text": a one-line Label or Button whose text is wider than its rect (cut
##     off or trimmed), or a wrapped Label taller than its rect.
##   - "overlap": two visible siblings placed by hand (their parent is not a
##     Container) whose rects cross; a sibling that fills its parent is its
##     background and may have things on it.
## Full-screen layers (scrims, the screen's own roots) are skipped: they cover
## everything on purpose. A child of a ScrollContainer is checked against the
## scroll's rect instead of the room.

const ROOM := Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
const TOP := float(SimConfig.KILL_TOP) / SimConfig.SUB
## Content keeps CLEAR px off the floor spike row: touching the tips reads as
## sitting on them.
const CLEAR := 8.0
const BOTTOM := float(SimConfig.KILL_BOTTOM) / SimConfig.SUB - CLEAR
## Archivo's cap and figure height, in em.
const CAP := 0.74
## Rounding slack, px.
const SLACK := 1.0


static func problems(screen: Control) -> Array[String]:
	var out: Array[String] = []
	var origin := screen.get_global_rect().position
	for c in screen.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not _shown(ctl) or _is_layer(ctl):
			continue
		var r := ctl.get_global_rect()
		r.position -= origin
		var scroll := _scroll_of(ctl)
		if scroll == null:
			if _draws(ctl) and not _inside_room(r):
				out.append("outside: %s at %s" % [_path(screen, ctl), r])
		_check_text(screen, ctl, out)
	_check_siblings(screen, screen, out)
	return out


static func _shown(c: Control) -> bool:
	return c.is_visible_in_tree() and c.modulate.a > 0.01 and c.size.x > 0.5 and c.size.y > 0.5


## A layer that covers the whole room on purpose (a scrim, a screen root).
static func _is_layer(c: Control) -> bool:
	return c.size.x >= ROOM.x - SLACK and c.size.y >= ROOM.y * 0.9


## Something the player sees: text, a picture, a filled box, a button.
static func _draws(c: Control) -> bool:
	if c is Label or c is BaseButton or c is TextureRect or c is LineEdit or c is ColorRect:
		return true
	if c is PanelContainer:
		var box := c.get_theme_stylebox("panel")
		return box != null and not box is StyleBoxEmpty
	return c.get_script() != null and c.has_method("_draw")


static func _inside_room(r: Rect2) -> bool:
	return (
		r.position.x >= -SLACK
		and r.end.x <= ROOM.x + SLACK
		and r.position.y >= TOP - SLACK
		and r.end.y <= BOTTOM + SLACK
	)


static func _scroll_of(c: Control) -> ScrollContainer:
	var up := c.get_parent()
	while up != null:
		if up is ScrollContainer:
			return up as ScrollContainer
		up = up.get_parent()
	return null


static func _check_text(screen: Control, c: Control, out: Array[String]) -> void:
	var text := ""
	var font: Font
	var size := 0
	var room := c.size.x
	if c is Label:
		var l := c as Label
		text = l.text
		font = l.get_theme_font("font")
		size = l.get_theme_font_size("font_size")
		var box := l.get_theme_stylebox("normal")
		if box != null:
			room -= box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			if l.get_minimum_size().y > l.size.y + SLACK and not l.clip_text:
				out.append("text: %s wraps taller than its rect" % _path(screen, c))
			return
		if l.visible_characters >= 0 and l.visible_characters < text.length():
			return
	elif c is Button:
		var b := c as Button
		if b.icon != null and not b.text.is_empty():
			return  # icon buttons lay out their own icon and name
		text = b.text
		font = b.get_theme_font("font")
		size = b.get_theme_font_size("font_size")
		var box := b.get_theme_stylebox("normal")
		if box != null:
			room -= box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	else:
		return
	if text.strip_edges().is_empty() or font == null:
		return
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	if widest > room + SLACK:
		out.append('text: %s "%s" needs %d px, has %d' % [_path(screen, c), text, widest, room])


## Hand-placed siblings must not cross: children of a plain Control (not a
## Container, which lays its children out itself).
static func _check_siblings(screen: Control, parent: Node, out: Array[String]) -> void:
	var placed: Array[Control] = []
	for c in parent.get_children():
		if not c is Control:
			continue
		var ctl := c as Control
		_check_siblings(screen, ctl, out)
		if parent is Container or not _shown(ctl) or _is_layer(ctl) or not _draws_any(ctl):
			continue
		if ctl.top_level or _fills(ctl, parent):
			continue
		placed.append(ctl)
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var a := ink_rect(placed[i]).grow(-SLACK)
			var b := ink_rect(placed[j]).grow(-SLACK)
			if a.intersects(b):
				out.append(
					"overlap: %s and %s" % [_path(screen, placed[i]), _path(screen, placed[j])]
				)


## The part of `c` that is drawn, in global px: a one-line Label's text where
## its alignment puts it (not the whole, often full-width, label), a bare icon
## button's icon; anything else its rect.
static func ink_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
		var l := c as Label
		var font := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var box := l.get_theme_stylebox("normal")
		if font == null or (box != null and not box is StyleBoxEmpty):
			return r
		var lines := l.text.split("\n")
		var w := 0.0
		for line in lines:
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var line_h := (
			font.get_ascent(fs) + font.get_descent(fs) + l.get_theme_constant("line_spacing")
		)
		var h := line_h * lines.size() - l.get_theme_constant("line_spacing")
		var x := r.position.x
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				x += (r.size.x - w) / 2.0
			HORIZONTAL_ALIGNMENT_RIGHT:
				x += r.size.x - w
		var y := r.position.y
		match l.vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				y += (r.size.y - h) / 2.0
			VERTICAL_ALIGNMENT_BOTTOM:
				y += r.size.y - h
		# The letters themselves: from cap height above the first baseline to
		# the last baseline (or the descenders, when the text has any).
		var low := 0.02
		for ch in "gjpqy,()":
			if l.text.contains(ch):
				low = 0.24
		var top := y + font.get_ascent(fs) - CAP * fs
		var bottom := y + font.get_ascent(fs) + line_h * (lines.size() - 1) + low * fs
		return Rect2(x, top, minf(w, r.size.x), bottom - top)
	if c is Button and (c as Button).text.is_empty() and (c as Button).icon != null:
		var b := c as Button
		var box := b.get_theme_stylebox("normal")
		if box == null or box is StyleBoxEmpty:
			var side := minf(minf(r.size.x, r.size.y), float(UiTokens.SIZE_ICON_M) + 8.0)
			return Rect2(r.get_center() - Vector2(side, side) / 2.0, Vector2(side, side))
	return r


## A background: it fills its parent, so what is placed on it is meant to be.
static func _fills(c: Control, parent: Node) -> bool:
	if not parent is Control:
		return false
	var p := (parent as Control).get_global_rect()
	var r := c.get_global_rect()
	return r.grow(SLACK).encloses(p)


## The control or anything under it draws.
static func _draws_any(c: Control) -> bool:
	if _draws(c):
		return true
	for d in c.find_children("*", "Control", true, false):
		if (d as Control).is_visible_in_tree() and _draws(d as Control):
			return true
	return false


static func _path(screen: Control, c: Control) -> String:
	var p := str(screen.get_path_to(c))
	var what := c.get_class()
	if c is Label or c is Button:
		what += ' "%s"' % (c.get("text") as String).left(24)
	return "%s(%s) at %s" % [p, what, c.get_global_rect()]
