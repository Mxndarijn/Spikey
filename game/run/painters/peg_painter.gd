extends HazardPainter
## Peg Field's peg: a round spiked peg in the spike colour, slowly turning, its
## spike tips exactly where it kills. The shared spiked-ball look.

const PegHazard := preload("res://sim/hazards/peg.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as PegHazard
	var r := HazardLayer.px(h.RADIUS)
	HazardLayer.spiky_ball(c, HazardLayer.at(h.x, h.y), r, look, look.time * 0.5 + h.x * 0.001)
