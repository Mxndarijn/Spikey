extends TestCase
## The reaction benchmark (ArrivalBench): out of a portal, a player who needs
## 0.75 s (ArrivalBench.EARLY_DELAY) to read the room, holding its height
## meanwhile, is never killed by it: every death there still had a way to live
## (SurvivalSearch finds one). At 1 s (SimConfig.ARRIVAL_BLIND) at most
## ArrivalBench.MAX_EXTRA_PCT of arrivals leave no way to live. A lighter
## PlannerBot plays (its deaths are only searched), so this stays fast; the
## full benchmark, with the full bot's death rate, runs on FastSim:
## `tools/fastsim.ps1 -Mode reaction` (and `-Mode odds` for real runs).

const PARALLEL := true
## The rooms are shared out over this many parts, which can run side by side.
const PARTS := 44
const COUNT := 8
const AFTER := 120
const HORIZON := 45
const ROLLOUTS := 2


func test_every_room_allows_a_slow_reaction_out_of_a_portal(part: int, parts: int) -> void:
	var total := 0
	var no_way := 0
	var killed: Array[String] = []
	for index in range(part, RoomCatalog.all().size(), parts):
		var early := ArrivalBench.play(
			index, COUNT, ArrivalBench.EARLY_DELAY, AFTER, HORIZON, ROLLOUTS, true
		)
		if early.forced > 0:
			killed.append("%s (%d of %d)" % [early.id, early.forced, COUNT])
		var late := ArrivalBench.play(
			index, COUNT, SimConfig.ARRIVAL_BLIND, AFTER, HORIZON, ROLLOUTS, true
		)
		total += COUNT
		no_way += late.forced
	assert_true(killed.is_empty(), "a 0.75 s reaction is killed in: %s" % ", ".join(killed))
	report = {"total": total, "no_way": no_way}


## The 1 s benchmark over every room together.
static func combine_test_every_room_allows_a_slow_reaction_out_of_a_portal(
	reports: Array
) -> Array[String]:
	var total := 0
	var no_way := 0
	for r: Dictionary in reports:
		total += int(r.total)
		no_way += int(r.no_way)
	if total != RoomCatalog.all().size() * COUNT:
		return ["only %d of %d arrivals ran" % [total, RoomCatalog.all().size() * COUNT]]
	if no_way * 100 > ArrivalBench.MAX_EXTRA_PCT * total:
		return ["a 1 s reaction leaves no way to live in %d of %d arrivals" % [no_way, total]]
	return []
