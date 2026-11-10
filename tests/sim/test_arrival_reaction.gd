extends TestCase
## The reaction benchmark: a player needs SimConfig.ARRIVAL_BLIND ticks (0.75 s)
## to read a room after a portal, holding its height meanwhile. In every room
## that slow reaction may cost at most ArrivalBench.MAX_EXTRA_PCT of arrivals
## over an instant one. A lighter PlannerBot keeps this fast; for the full
## benchmark (60 arrivals per room, full PlannerBot) run tools/arrival_bench.gd.

const COUNT := 8
const AFTER := 120
const HORIZON := 45
const ROLLOUTS := 2


func test_every_room_allows_a_slow_reaction_out_of_a_portal() -> void:
	var total := 0
	var extra := 0
	var failed: Array[String] = []
	for index in RoomCatalog.all().size():
		var r := ArrivalBench.room(index, COUNT, SimConfig.ARRIVAL_BLIND, AFTER, HORIZON, ROLLOUTS)
		total += COUNT
		extra += maxi(r.extra, 0)
		# Eight arrivals can't tell 5% from 10%: per room this only catches a
		# broken room; the benchmark itself holds over all rooms together.
		if r.extra > 2:
			failed.append("%s (%d extra of %d)" % [r.id, r.extra, COUNT])
	assert_true(failed.is_empty(), "rooms over the benchmark: %s" % ", ".join(failed))
	assert_true(
		extra * 100 <= ArrivalBench.MAX_EXTRA_PCT * total,
		"slow reactions cost %d of %d arrivals" % [extra, total]
	)
