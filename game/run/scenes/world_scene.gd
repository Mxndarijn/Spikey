class_name WorldScene
extends RefCounted
## How one world looks beyond its colours (ThemeDef): its landscape, what
## falls through its sky and the touch it adds to a Match my world portal.
## Each world has one in game/run/scenes/worlds/<id>.gd (WorldScenes finds it
## by id; a world without one gets generic.gd), so everything about a world's
## look is in one file.

## Falling things ("snow", "embers", "sprinkles", "leaves", "petals",
## "bubbles"; "" for a calm sky), how many, and the band they move in (top,
## bottom), px. RoomView draws them.
var mote_kind := ""
var mote_count := 0
var mote_band := Vector2(RoomView.MOTE_TOP, 480.0)


## Paints the landscape over the sky (the pen has the sky stops already).
func paint(_pen: ScenePen, _t: ThemeDef) -> void:
	pass


## The colours of the world's touch on a Match my world portal's rim; empty
## for none.
func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return []


## Draws that touch round the rim (PortalPainter.rim gives the points).
func draw_portal_touch(_p: PortalPen, _t: ThemeDef, _cols: Array[Color]) -> void:
	pass
