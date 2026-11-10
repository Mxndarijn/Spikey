class_name HazardPainter
extends RefCounted
## Draws one hazard kind. Each kind has one in
## game/run/painters/<kind>_painter.gd that extends this, casts the hazard to
## its own class and reads only its public fields. Looks only: never changes
## the hazard.


## Draws `hazard` (always of this painter's kind) on `c`.
func paint(_c: CanvasItem, _hazard: Hazard, _look: HazardLook) -> void:
	pass


## 0..1: how far the floor spike whose base runs from `left` to `right` (px)
## has sunk into the floor under `hazard` (1 = gone). Only for spikes wholly
## inside the hazard's deadly area, so the floor never looks safe where it
## is not. RoomView asks this for every floor spike.
func floor_sink(_hazard: Hazard, _left: float, _right: float) -> float:
	return 0.0
