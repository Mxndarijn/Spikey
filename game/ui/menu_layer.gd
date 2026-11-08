class_name MenuLayer
extends CanvasLayer
## Holds the current menu screen (home, customize, rooms, leaderboards) above
## the room. One screen at a time; the room keeps animating behind it.
## The screens' theme follows the world: white room text on night rooms.

var _root := Control.new()
var _current: Control


func _init() -> void:
	layer = 2
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)


## UiTheme.room_theme(world) for the world in use.
func set_room_theme(t: Theme) -> void:
	_root.theme = t


func room_theme() -> Theme:
	return _root.theme


func show_screen(screen: Control) -> void:
	clear()
	_current = screen
	_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func clear() -> void:
	if _current != null:
		_current.queue_free()
		_current = null


func current() -> Control:
	return _current
