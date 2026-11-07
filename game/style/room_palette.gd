class_name RoomPalette
extends Resource
## Sky stops for one room (a time of day) inside a world. The world's spike
## color must stay 3:1 or more against every stop (tests/unit/test_design_kit.gd).

@export var name := ""
@export var sky_top := Color.WHITE
@export var sky_mid := Color.WHITE
@export var sky_bottom := Color.WHITE


func stops() -> Array[Color]:
	return [sky_top, sky_mid, sky_bottom]
