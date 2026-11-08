class_name ScreenLayout
extends RefCounted
## Where the 360 x 640 room sits on a phone of any shape.
## The project stretches with aspect "expand": the screen is at least 360 x 640
## and grows taller (or wider) to fill the phone, so there are no black bars.
## The room keeps its size on every phone (fair leaderboards) and sits centred
## in the safe area (clear of notches and the home bar) when it fits there.
## The world, the HUD and the menus all use the same room rect; RoomView fills
## the space around it with the spike band colour.

const ROOM := Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)


## The room's rect on a screen of `visible` size (canvas px), with `safe` the
## area clear of notches. Per axis: centred in the safe area when the room fits
## there, else centred on the screen. Whole pixels, so lines stay crisp.
static func room_rect(visible: Vector2, safe: Rect2) -> Rect2:
	var pos := Vector2.ZERO
	for axis in 2:
		var room := ROOM[axis]
		var from := 0.0
		var span := visible[axis]
		if safe.size[axis] >= room:
			from = safe.position[axis]
			span = safe.size[axis]
		var at := from + (span - room) / 2.0
		pos[axis] = clampf(roundf(at), 0.0, maxf(0.0, visible[axis] - room))
	return Rect2(pos, ROOM)


## The safe area in canvas px. `window` and `safe_px` are in screen pixels (as
## DisplayServer gives them); a missing or useless safe area means the whole
## screen is safe.
static func safe_rect(visible: Vector2, window: Rect2i, safe_px: Rect2i) -> Rect2:
	var whole := Rect2(Vector2.ZERO, visible)
	if window.size.x <= 0 or window.size.y <= 0:
		return whole
	var local := Rect2(safe_px).intersection(Rect2(window))
	if local.size.x <= 0.0 or local.size.y <= 0.0:
		return whole
	var scale := visible / Vector2(window.size)
	return Rect2((local.position - Vector2(window.position)) * scale, local.size * scale)


## The room rect for the running app's window.
static func current(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect().size
	var window := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var safe := safe_rect(visible, window, DisplayServer.get_display_safe_area())
	return room_rect(visible, safe)
