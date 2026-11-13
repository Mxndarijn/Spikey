class_name RaftLanding
extends RefCounted
## Lava Rise rafts, for looks only: the sim uses a raft up on its first touch
## (Lava.touch), so a raft that was up last frame and is gone now was landed
## on. The lava painter (dip, splash) and BirdView (squash) both ask here.
## Reads sim state, never changes it.

const LavaHazard := preload("res://sim/hazards/lava.gd")


## The rafts of `h` landed on since the last call with the same `seen` (a
## dictionary the caller keeps: "<hazard id>:<raft>" -> was up).
static func landed(h: LavaHazard, seen: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in LavaHazard.MAX_RAFTS:
		var key := "%d:%d" % [h.get_instance_id(), i]
		if seen.get(key, false) and not h.raft_on[i] and h.raft_age[i] >= LavaHazard.RAFT_RISE:
			out.append(i)
		seen[key] = h.raft_on[i] and h.raft_age[i] >= LavaHazard.RAFT_RISE
	return out
