class_name HazardLook
extends RefCounted
## How the hazards are drawn this frame: the world's colours, the clock for
## animation, the room's skin and whether color-blind spikes are on.

## The run score's top in a normal run (Hud._place_score).
const RUN_SCORE_TOP := 34.0

## The world the painters use. With `ink` on, a copy whose spike colour is ink
## and whose spike edge is white (HazardLayer.ink_theme).
var theme: ThemeDef
## Seconds since the layer started, for animation only.
var time := 0.0
## The room's cosmetic variant (RoomSkins.of), "" for the usual look.
var skin := ""
## Color-blind spikes: deadly shapes get a white outline.
var ink := false
## The run being drawn (read only), for painters whose shapes depend on more
## than their hazard (a beam stopping at an exit's mouth). Null in previews.
var sim: GameSim = null
## Top of the HUD's run score, px: lower while a practice or replay banner shows.
var score_top := RUN_SCORE_TOP


func _init(
	p_theme: ThemeDef, p_time: float = 0.0, p_skin: String = "", p_ink: bool = false
) -> void:
	theme = p_theme
	time = p_time
	skin = p_skin
	ink = p_ink
