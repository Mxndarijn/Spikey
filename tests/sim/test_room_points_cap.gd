extends TestCase
## No room pays more than POINTS_PER_ROOM points: once the exit opens, bounces
## stop scoring until the bird leaves. Checked in every room and every variant,
## and across a revive (it restarts the room but keeps the open exit).
##
## The full check runs on FastSim (`tools/fastsim.ps1 -Mode check -Check
## points`, part of tools/check.ps1) with more seeds and revive runs
## (Checks.cs SEEDS_PER_VARIANT, REVIVE_RUNS). Here the real sim plays the
## first of them.

const PARALLEL := true

const SEEDS_PER_VARIANT := 1
const MAX_TICKS := 6000
const REVIVE_RUNS := 10

## Room stays that reached the full POINTS_PER_ROOM (so the cap was really hit).
var _full_stays := 0


func test_every_room_and_variant_pays_at_most_one_room_of_points() -> void:
	var rooms := RoomCatalog.all()
	for index in rooms.size():
		var def := rooms[index]
		var variants: Array[String] = [""]
		for v: RoomVariant in def.variants:
			variants.append(v.id)
		for variant in variants:
			for n in SEEDS_PER_VARIANT:
				var sim := GameSim.new(1000 + index * 37 + n, def.season, index, variant)
				if not _play_and_check(sim, "%s/%s seed %d" % [def.id, variant, n]):
					return
	print("    room stays that hit the cap: %d" % _full_stays)
	assert_true(_full_stays > rooms.size(), "the bot reaches the cap in many rooms")


func test_a_revive_never_pays_a_room_twice() -> void:
	var seeds := SimRng.new(4242)
	for run in REVIVE_RUNS:
		var sim := GameSim.new(seeds.next_u32())
		if not _play_and_check(sim, "run %d" % run, true):
			return


## Plays with the gap seeker and fails if one stay in a room (from arriving to
## leaving, revives included) scores more than POINTS_PER_ROOM.
func _play_and_check(sim: GameSim, label: String, revive: bool = false) -> bool:
	var bot := SimRng.new(7)
	var room_index := sim.state.room_index
	var entry_score := sim.state.score
	while sim.state.tick < MAX_TICKS:
		if sim.is_over():
			if not (revive and sim.can_revive() and sim.revive()):
				break
		sim.step(SimBots.gap_seeker(sim, bot))
		if sim.state.room_index != room_index:
			if sim.state.score - entry_score == SimConfig.POINTS_PER_ROOM:
				_full_stays += 1
			room_index = sim.state.room_index
			entry_score = sim.state.score
		var gained := sim.state.score - entry_score
		if gained > SimConfig.POINTS_PER_ROOM or sim.room.points > SimConfig.POINTS_PER_ROOM:
			fail("%s: %d points in one room (tick %d)" % [label, gained, sim.state.tick])
			return false
	return true
