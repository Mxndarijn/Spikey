extends TestCase
## The reaction benchmark (ArrivalBench): out of a portal, a player who needs
## 0.75 s (ArrivalBench.EARLY_DELAY) to read the room, holding its height
## meanwhile, is never killed by it: every death there still had a way to live
## (SurvivalSearch finds one). At 1 s (SimConfig.ARRIVAL_BLIND) at most
## ArrivalBench.MAX_EXTRA_PCT of arrivals leave no way to live.
##
## The full check runs on FastSim (`tools/fastsim.ps1 -Mode check -Check
## arrival`, part of tools/check.ps1): both rules over every room and variant,
## Checks.cs COUNT arrivals each. Here the real sim plays the 0.75 s rule on
## every SAMPLE_EVERY-th case, COUNT arrivals each. A lighter PlannerBot plays
## (its deaths are only searched, so the result does not hang on the bot). The
## full benchmark, with the full bot's death rate: `tools/fastsim.ps1 -Mode
## reaction` (and `-Mode odds` for real runs).

const PARALLEL := true
## The cases are shared out over this many parts, which can run side by side.
const PARTS := 4
const COUNT := 6
const SAMPLE_EVERY := 8
const AFTER := 120
const HORIZON := 45
const ROLLOUTS := 2


## Every SAMPLE_EVERY-th of every room and every variant of it on its own
## (ArrivalBench.cases).
func test_a_sample_of_rooms_allows_a_slow_reaction_out_of_a_portal(part: int, parts: int) -> void:
	var killed: Array[String] = []
	var cases := ArrivalBench.cases()
	for c in range(part * SAMPLE_EVERY, cases.size(), parts * SAMPLE_EVERY):
		var index: int = cases[c][0]
		var variant: String = cases[c][1]
		var early := ArrivalBench.play(
			index, COUNT, ArrivalBench.EARLY_DELAY, AFTER, HORIZON, ROLLOUTS, true, variant
		)
		if early.forced > 0:
			killed.append("%s (%d of %d)" % [early.id, early.forced, COUNT])
	assert_true(killed.is_empty(), "a 0.75 s reaction is killed in: %s" % ", ".join(killed))
