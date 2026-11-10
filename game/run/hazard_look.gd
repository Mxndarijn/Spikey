class_name HazardLook
extends RefCounted
## How the hazards are drawn this frame: the world's colours, the clock for
## animation, the room's skin and whether color-blind spikes are on.

## The world the painters use. With `ink` on, a copy whose spike colour is ink
## and whose spike edge is white (HazardLayer.ink_theme).
var theme: ThemeDef
## Seconds since the layer started, for animation only.
var time := 0.0
## The room's cosmetic variant (RoomSkins.of), "" for the usual look.
var skin := ""
## Color-blind spikes: deadly shapes get a white outline.
var ink := false


func _init(
	p_theme: ThemeDef, p_time: float = 0.0, p_skin: String = "", p_ink: bool = false
) -> void:
	theme = p_theme
	time = p_time
	skin = p_skin
	ink = p_ink
