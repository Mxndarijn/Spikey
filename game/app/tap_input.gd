class_name TapInput
extends RefCounted
## What counts as a tap in a run: a left click or touch, or Space; and one
## key press (no echo).


static func is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return is_key(event, KEY_SPACE)


static func is_key(event: InputEvent, key: Key) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.keycode == key
	return false
