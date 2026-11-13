class_name HaloIcon
extends Control
## An icon in the HUD's halo (UiTheme.HUD_HALO): a ring of ink copies under the
## icon, so it stands out from any room behind it, light or dark. White icons
## (pause, back, tap) are drawn in UiTheme.HUD_FILL; coloured ones (the coin)
## keep their colours. Centred in the control at `icon_size`.

## Copies in the ring: enough for a round edge at HALO_ICON px.
const RING_STEPS := 12

var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
var icon_size := float(UiTokens.SIZE_ICON_M):
	set(value):
		icon_size = value
		queue_redraw()
## White icons take the HUD fill; coloured ones keep their own colours.
var tinted := true


func _init(icon: Texture2D = null, side: float = UiTokens.SIZE_ICON_M, tint := true) -> void:
	texture = icon
	icon_size = side
	tinted = tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)


func _draw() -> void:
	if texture == null:
		return
	var box := Rect2((size - Vector2(icon_size, icon_size)) / 2.0, Vector2(icon_size, icon_size))
	for i in RING_STEPS:
		var a := TAU * i / RING_STEPS
		var shift := Vector2(cos(a), sin(a)) * UiTheme.HALO_ICON
		draw_texture_rect(texture, Rect2(box.position + shift, box.size), false, UiTheme.HUD_HALO)
	draw_texture_rect(texture, box, false, UiTheme.HUD_FILL if tinted else Color.WHITE)
