extends TestCase
## Caterpillar Crawl (and Summer Crab Walk): no two crawlers ever overlap, at
## the room start or anywhere round their path, in every variant, out of a
## portal at any height (the recipe's own tries and its fallback).

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const SUB := SimConfig.SUB
const Crawler := preload("res://sim/hazards/crawler.gd")
const ROOMS: Array[String] = ["crawl", "crabs"]
const SEEDS := 6
const HEIGHTS: Array[int] = [130, 230, 310, 330, 430, 520]
## Steps between looks (a crawler moves at most 2 px a step).
const EVERY := 4


## Out of a portal: the layout the room builds (its own tries, a fallback
## when every try fails).
func test_crawlers_never_overlap_out_of_a_portal() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			for s in SEEDS:
				for y_px in HEIGHTS:
					for side in 2:
						var sim := _arrived(index, v.id, s, y_px, side)
						var label := "%s/%s seed %d at %d px, side %d" % [id, v.id, s, y_px, side]
						_assert_apart(sim, label)


## The fallback layout, forced at every height: only the crawlers that start
## on the edge away from the bird, half of them.
func test_crawlers_never_overlap_in_the_fallback() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			for s in SEEDS:
				for y_px in HEIGHTS:
					var sim := _arrived(index, v.id, s, y_px, s % 2)
					sim.room.hazards.clear()
					var p := VariantParams.make(sim, SimRng.new(9000 + s))
					p.attempt = RoomVariant.GENERATE_TRIES - 1
					p.fallback = true
					assert_true(p.arriving, "out of a portal")
					v.recipe.call(p)
					var label := "%s/%s fallback seed %d at %d px" % [id, v.id, s, y_px]
					var away := 1 if p.entry_y < SimConfig.WORLD_H / 2 else 0
					var count := 0
					for h in sim.room.hazards:
						if h.kind == "crawler":
							count += 1
							assert_eq(h.lane, away, "%s: on the edge away from the bird" % label)
					assert_eq(count, 2 if v.id == "swarm" else 1, "%s: half the crawlers" % label)
					_assert_apart(sim, label)


## At the start of a run or practice (no portal).
func test_crawlers_never_overlap_at_a_practice_start() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		for s in SEEDS * 4:
			var sim := GameSim.new(s + 1, def.season, index)
			_assert_apart(sim, "%s practice seed %d" % [id, s + 1])


static func _arrived(index: int, variant: String, s: int, anchor_px: int, side: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(7300 + s * 31 + anchor_px + side, def.season)
	sim.forced_variant = variant
	sim.step(true)
	sim.state.score = maxi(def.from_score, 20)
	sim.state.anchor_y = GameSim._arrival_y(anchor_px * SUB)
	sim.state.y = sim.state.anchor_y
	sim._arrive_in(side, index)
	return sim


## Walks every crawler once round its whole path (all walk at one speed, so
## this is every layout the room can show) and checks no segments of two
## crawlers touch.
func _assert_apart(sim: GameSim, label: String) -> void:
	var crawlers: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == "crawler":
			crawlers.append(h)
	assert_true(crawlers.size() >= 1, "%s: crawlers built" % label)
	var t0: int = crawlers[0].t
	for t in range(t0, t0 + Crawler.PERIMETER / Crawler.SPEED, EVERY):
		for h in crawlers:
			h.t = t
			h._place()
		var hit := _touching(crawlers)
		if hit != "":
			assert_true(false, "%s, step %d: %s" % [label, t - t0, hit])
			return
	for h in crawlers:
		h.t = t0
		h._place()


static func _touching(crawlers: Array[Hazard]) -> String:
	for a in crawlers.size():
		var ca: Hazard = crawlers[a]
		for b in range(a + 1, crawlers.size()):
			var cb: Hazard = crawlers[b]
			var reach: int = ca.seg_radius + cb.seg_radius
			for i in ca.xs.size():
				for j in cb.xs.size():
					var dx: int = ca.xs[i] - cb.xs[j]
					var dy: int = ca.ys[i] - cb.ys[j]
					if dx * dx + dy * dy <= reach * reach:
						return "crawlers %d and %d touch" % [a, b]
	return ""
