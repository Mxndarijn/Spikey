class_name SimClone
extends RefCounted
## Deep copies a GameSim for planners and searches in tests and tools. The
## copying itself lives in the sim (SimCopy), which uses it for ArrivalCheck.


static func copy(sim: GameSim) -> GameSim:
	return SimCopy.copy(sim)
