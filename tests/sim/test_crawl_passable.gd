extends TestCase
## Caterpillar Crawl (and Summer Crab Walk, the same hazard): a crawler on a
## wall side must never stand in front of the only bounce spot or the exit.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const SUB := SimConfig.SUB
const Crawler := preload("res://sim/hazards/crawler.gd")
const ROOMS: Array[String] = ["crawl", "crabs"]

## SurvivalSearch cases: [room id, practice seed]. Long enough for the ten
## bounces to the first portal and the first bounces after it. On these seeds,
## before the fix, a crawler covered the whole exit opening (22, 89) or every
## free wall slot (64) as the bird flew in.
const SEARCH_TICKS := 1000
const SEARCH_CASES := [["crawl", 22], ["crawl", 64], ["crabs", 89]]
## One search case per part, so they can run side by side.
const PARTS := 3

## The sweep: practice seeds per room, and ticks each (two to three portals).
const SWEEP_SEEDS := 60
const SWEEP_TICKS := 2400
## The bird can touch a segment on a wall's side of the path only this close
## to that wall (the path is 60 px in, the two radii are 24 px).
const NEAR_WALL := 80 * SUB
## Bird and segment centres this close: dead.
const TOUCH := Crawler.SEG_RADIUS + SimConfig.BIRD_RADIUS
## Free slots in a row every wall must keep clear of the crawlers.
const MIN_RUN := 3


## A crawler that walks as usual but never kills, so one bird can fly the whole
## room at any height while the test watches where the crawlers get in the way.
class Harmless:
	extends Crawler

	func kills(_sim: GameSim) -> bool:
		return false


func test_search_gets_past_the_first_portal(part: int, parts: int) -> void:
	for i in range(part, SEARCH_CASES.size(), parts):
		var c: Array = SEARCH_CASES[i]
		var index := RoomCatalog.index_of(c[0])
		var def: RoomDef = RoomCatalog.all()[index]
		var sim := GameSim.new(c[1], def.season, index)
		var search := SurvivalSearch.new()
		var ok := search.run(sim, SEARCH_TICKS)
		assert_true(
			ok,
			(
				"%s seed %d: all died at tick %d (%s)"
				% [c[0], c[1], search.ticks_survived, search.last_deaths]
			)
		)
		if ok:
			assert_true(search.best.state.room_index >= 1, "%s seed %d: took the portal" % c)


## Flies a bird that cannot die through many practice runs, at a new height
## after every bounce, and watches the real crawler positions each step:
## - every wall keeps MIN_RUN slots in a row with no spike and no crawler in
##   front of them while the bird is at that wall, and
## - no crawler is in front of any part of an open exit as the bird flies in.
func test_crawlers_never_cover_the_way_on() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		var walls := 0
		var exits := 0
		for s in range(1, SWEEP_SEEDS + 1):
			var sim := GameSim.new(s, def.season, index)
			var counts := _sweep(sim, "%s seed %d" % [id, s])
			walls += counts[0]
			exits += counts[1]
		assert_true(walls > SWEEP_SEEDS * 20, "%s: checked many walls (%d)" % [id, walls])
		assert_true(exits >= SWEEP_SEEDS * 2, "%s: checked many exits (%d)" % [id, exits])


## A revive starts the room again while the exit stays where it was planned,
## for crawlers that were somewhere else. The fresh crawlers come down the wall
## sides near the top right and bottom left corners, so exits there are the
## hard ones: they start further back and still leave the exit clear.
func test_revive_leaves_the_planned_exit_clear() -> void:
	var index := RoomCatalog.index_of("crawl")
	var top := SimConfig.slot_center_y(1)
	var bottom := SimConfig.slot_center_y(SimConfig.SLOT_COUNT - 2)
	for s in range(1, 31):
		for exit: String in ["open", "ghost"]:
			for side in 2:
				for y: int in [top, bottom]:
					var sim := _revived(index, s, exit, side, y)
					var label := "seed %d, %s exit on wall %d at %d px" % [s, exit, side, y / SUB]
					for h: Hazard in sim.room.hazards:
						assert_false(h.blocks_exit(sim, side, y), "%s: clear of the exit" % label)
						assert_false(h.kills(sim), "%s: clear of the bird" % label)
	# And all the way: the search flies from the revive through the hard exits.
	for c: Array in [
		["ghost", 1, top], ["ghost", 0, bottom], ["open", 1, top], ["open", 0, bottom]
	]:
		var sim := _revived(index, 7, c[0], c[1], c[2])
		var search := SurvivalSearch.new()
		var ok := search.run(sim, SimConfig.ARRIVAL_HOLD + 240)
		assert_true(ok, "%s exit on wall %d: all died after the revive" % [c[0], c[1]])
		if ok:
			assert_eq(search.best.state.room_index, 1, "%s exit on wall %d: taken" % [c[0], c[1]])


## A real run in room `index` with an exit ("open" or "ghost") on wall `side`
## at height `y`, killed there and revived.
static func _revived(index: int, seed_value: int, exit: String, side: int, y: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(seed_value, def.season)
	sim.step(true)
	# Not a fork score, so there is one exit.
	var base := 60
	sim.state.score = base + 3
	sim._enter_room(index)
	if exit == "open":
		sim.state.score = base
		sim._plan_exit(side, base)
		sim.state.exit_open = true
	else:
		sim.state.score = base + SimConfig.POINTS_PER_ROOM - 1
		sim._plan_exit(side, base + SimConfig.POINTS_PER_ROOM)
		sim.state.exit_preview = true
	sim.state.exit_a_y = y
	sim.kill(SimState.DeathCause.FLOOR)
	sim.revive()
	return sim


## Returns [walls checked, exits checked].
func _sweep(sim: GameSim, label: String) -> Array[int]:
	var s := sim.state
	_make_harmless(sim)
	# Spikes of each wall as generated (the test takes them off the wall so
	# the bird lives), and the slots a crawler was in front of.
	var spikes: Array[int] = [0, 0]
	var covered: Array[int] = [0, 0]
	var ahead := 1 if s.vx > 0 else 0
	spikes[ahead] = sim.wall_mask(ahead)
	s.left_spikes = 0
	s.right_spikes = 0
	# A wall is judged once the bird has left it: [side, steps to go].
	var pending: Array[int] = []
	var bounces := 0
	var exit_gap := Crawler.FAR
	var walls := 0
	var exits := 0
	for tick in SWEEP_TICKS:
		s.y = s.exit_a_y if s.exit_open else (100 + (sim.seed_value * 7 + bounces * 53) % 440) * SUB
		s.vy = 0
		sim.step(tick == 0)
		assert_true(s.alive, "%s: the test bird lives (tick %d)" % [label, tick])
		if not s.alive:
			break
		if sim.events.has(GameSim.Event.ROOM_CHANGE):
			exits += 1
			assert_true(
				exit_gap >= SimConfig.EXIT_FIT + TOUCH,
				(
					"%s tick %d: a crawler %d px from the exit's centre as the bird flew in"
					% [label, tick, exit_gap / SUB]
				)
			)
			exit_gap = Crawler.FAR
			_make_harmless(sim)
			covered = [0, 0]
			pending.clear()
			ahead = 1 if s.vx > 0 else 0
			spikes[ahead] = sim.wall_mask(ahead)
			s.left_spikes = 0
			s.right_spikes = 0
			continue
		if sim.events.has(GameSim.Event.BOUNCE):
			bounces += 1
			pending = [ahead, NEAR_WALL / SimConfig.SPEED_X]
			ahead = 1 - ahead
			# Whatever was near the bird when it started at that wall is old news.
			covered[ahead] = 0
			spikes[ahead] = sim.wall_mask(ahead)
			s.left_spikes = 0
			s.right_spikes = 0
		# Where the crawlers are in the bird's way right now.
		var r := SimConfig.BIRD_RADIUS
		for side in 2:
			var wall := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
			if absi(s.x - wall) > NEAR_WALL:
				continue
			for h: Hazard in sim.room.hazards:
				for i: int in h.xs.size():
					if absi(h.xs[i] - s.x) > TOUCH:
						continue
					var y: int = h.ys[i]
					if s.exit_open and s.exit_side == side:
						exit_gap = mini(exit_gap, absi(y - s.exit_a_y))
					for slot in SimConfig.SLOT_COUNT:
						var cy := SimConfig.slot_center_y(slot)
						if absi(cy - y) <= SimConfig.SLOT_SIZE / 2 + TOUCH:
							covered[side] |= 1 << slot
		if pending.is_empty():
			continue
		pending[1] -= 1
		if pending[1] > 0:
			continue
		var side := pending[0]
		pending.clear()
		walls += 1
		var run := RoomRules.longest_gap(spikes[side] | covered[side])
		assert_true(
			run >= MIN_RUN,
			(
				"%s tick %d wall %d: only %d free slots in a row (spikes %s, crawlers %s)"
				% [label, tick, side, run, _bits(spikes[side]), _bits(covered[side])]
			)
		)
	return [walls, exits]


## A slot mask from the top slot down: # for a set slot, . for a clear one.
static func _bits(mask: int) -> String:
	var out := ""
	for slot in SimConfig.SLOT_COUNT:
		out += "#" if RoomRules.has_slot(mask, slot) else "."
	return out


## Swaps the room's crawlers for harmless ones in the same place.
static func _make_harmless(sim: GameSim) -> void:
	for i in sim.room.hazards.size():
		var from: Hazard = sim.room.hazards[i]
		var h := Harmless.new(from.lane)
		h.skin = from.skin
		h.t = from.t
		h.start = from.start
		h.xs = from.xs.duplicate()
		h.ys = from.ys.duplicate()
		sim.room.hazards[i] = h
