extends TestCase
## Caterpillar Crawl (and Summer Crab Walk, the same hazard): a crawler on a
## wall side must never stand in front of the only bounce spot or the exit.
## The SurvivalSearch cases (through the first portal, and from a revive
## through the hard exits) run on FastSim-RS: `tools/fastsim.ps1 -Mode check
## -Check crawl` (tools/fastsim-rs/fastsim/src/checks/searches.rs), part of
## tools/check.ps1.

## Each test can run in a worker of its own (tests/run_tests.gd).
const PARALLEL := true

const SUB := SimConfig.SUB
const Crawler := preload("res://sim/hazards/crawler.gd")
const ROOMS: Array[String] = ["crawl", "crabs"]

## The sweep: practice seeds per room, and ticks each (two to three portals).
const SWEEP_SEEDS := 60
const SWEEP_TICKS := 2400
## The sweep's runs are shared out over this many parts, which can run side by side.
const PARTS := 6
## The bird can touch a segment on a wall's side of the path only this close
## to that wall (the path is 60 px in, the two radii are 24 px).
const NEAR_WALL := 80 * SUB
## Bird and segment centres this close: dead (for the classic crawler; each
## crawler's own radius is used in the sweep).
const TOUCH := Crawler.SEG_RADIUS + SimConfig.BIRD_RADIUS
## Free slots in a row every wall must keep clear of the crawlers.
const MIN_RUN := 3


## A crawler that walks as usual but never kills, so one bird can fly the whole
## room at any height while the test watches where the crawlers get in the way.
class Harmless:
	extends Crawler

	func kills(_sim: GameSim) -> bool:
		return false


## Flies a bird that cannot die through many practice runs, at a new height
## after every bounce, and watches the real crawler positions each step:
## - every wall keeps MIN_RUN slots in a row with no spike and no crawler in
##   front of them while the bird is at that wall, and
## - no crawler is in front of any part of an open exit as the bird flies in.
func test_crawlers_never_cover_the_way_on(part: int, parts: int) -> void:
	var counts := {}
	for i in range(part, ROOMS.size() * SWEEP_SEEDS, parts):
		var id := ROOMS[i / SWEEP_SEEDS]
		var s := i % SWEEP_SEEDS + 1
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		var got := _sweep(GameSim.new(s, def.season, index), "%s seed %d" % [id, s])
		var sum: Array = counts.get(id, [0, 0])
		counts[id] = [sum[0] + got[0], sum[1] + got[1]]
	report = counts


## Over every part: each room had many walls and exits checked.
static func combine_test_crawlers_never_cover_the_way_on(reports: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ROOMS:
		var walls := 0
		var exits := 0
		for r: Dictionary in reports:
			var c: Array = r.get(id, [0, 0])
			walls += int(c[0])
			exits += int(c[1])
		if walls <= SWEEP_SEEDS * 20:
			out.append("%s: checked many walls (%d)" % [id, walls])
		if exits < SWEEP_SEEDS * 2:
			out.append("%s: checked many exits (%d)" % [id, exits])
	return out


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
				var touch: int = h.seg_radius + SimConfig.BIRD_RADIUS
				for i: int in h.xs.size():
					if absi(h.xs[i] - s.x) > touch:
						continue
					var y: int = h.ys[i]
					if s.exit_open and s.exit_side == side:
						# Measured as if it were a classic crawler: minus its own reach.
						exit_gap = mini(exit_gap, absi(y - s.exit_a_y) - touch + TOUCH)
					for slot in SimConfig.SLOT_COUNT:
						var cy := SimConfig.slot_center_y(slot)
						if absi(cy - y) <= SimConfig.SLOT_SIZE / 2 + touch:
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
		h.t = from.t
		h.start = from.start
		h.segments = from.segments
		h.seg_radius = from.seg_radius
		h.spacing = from.spacing
		h.speed = from.speed
		h.reserve = from.reserve
		h.trails = from.trails
		h.xs = from.xs.duplicate()
		h.ys = from.ys.duplicate()
		sim.room.hazards[i] = h
