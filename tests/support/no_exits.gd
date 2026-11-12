class_name NoExits
extends RefCounted
## For tests of how a hazard moves: takes away the room's planned exits, so no
## exit mouth (ExitZone) is in its way. tests/sim/test_exit_clear.gd tests the
## mouths themselves.


static func clear(sim: GameSim) -> void:
	sim.state.plan_a_y_left = 0
	sim.state.plan_b_y_left = 0
	sim.state.plan_a_y_right = 0
	sim.state.plan_b_y_right = 0
