class_name HazardPainter
extends RefCounted
## Draws one hazard kind. Each kind has one in
## game/run/painters/<kind>_painter.gd that extends this, casts the hazard to
## its own class and reads only its public fields. Looks only: never changes
## the hazard.


## Draws `hazard` (always of this painter's kind) on `c`.
func paint(_c: CanvasItem, _hazard: Hazard, _look: HazardLook) -> void:
	pass
