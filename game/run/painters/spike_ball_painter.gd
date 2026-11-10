extends HazardPainter
## Spike ball (Coin Garden, Spiked Decoy): a still spiked ball in the spike
## colour, slowly turning, on one of the coin spots. Never gold and never
## coin-shaped, so it reads as deadly at a glance.

const SpikeBallHazard := preload("res://sim/hazards/spike_ball.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as SpikeBallHazard
	var r := HazardLayer.px(h.RADIUS)
	HazardLayer.spiky_ball(c, HazardLayer.at(h.x, h.y), r, look, look.time * 0.8)
