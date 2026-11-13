extends TestCase
## Rooms keep a fair way through for a player who reacts in about 1 s
## (planner review, fairness): the boss's wall keeps a whole safe free run,
## crates aren't marked where the bird can neither pass under nor over them,
## Squeeze Box steers its free runs, and the top and bottom wall spikes leave
## no lane by the ceiling or floor.

const RoomsTest := preload("res://tests/unit/test_rooms.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Updraft := preload("res://sim/hazards/updraft.gd")

const SUB := SimConfig.SUB
const ALL := (1 << SimConfig.SLOT_COUNT) - 1


static func _hazard(sim: GameSim, kind: String) -> Hazard:
	for h in sim.room.hazards:
		if h.kind == kind:
			return h
	return null


## Longest run of slots that are free in `mask` and set in `ok`.
static func _free_ok(mask: int, ok: int) -> int:
	return RoomRules.longest_gap(mask | (ALL & ~ok))


func test_keep_run_clears_a_run_inside_the_allowed_slots_near_the_free_run() -> void:
	var ok := 0b0000_0011_1111_0
	# Free run at slots 9..12, outside `ok`.
	var mask := ALL & ~(0b1111 << 9)
	var out := RoomRules.keep_run(mask, 4, ok)
	assert_true(_free_ok(out, ok) >= 4, "a run of 4 inside ok")
	assert_eq(out & ~ok, mask & ~ok, "nothing cleared outside ok")
	# The cleared run is the one nearest the old free run (slots 3..6).
	assert_eq(out & ok, ok & ~(0b1111 << 3))
	assert_eq(RoomRules.keep_run(out, 4, ok), out, "already fine: unchanged")
	assert_eq(RoomRules.keep_run(mask, 7, ok), mask, "ok too narrow: unchanged")


func test_a_boss_wall_keeps_a_whole_safe_free_run() -> void:
	var checked := 0
	for id: String in ["boss_watcher", "boss_crusher", "boss_saw"]:
		for seed_value in range(1, 5):
			var sim := RoomsTest.sim_in_room(id, seed_value)
			var boss := _hazard(sim, id)
			for p: int in [1, 2, 3]:
				boss.phase = p
				for k: int in range(0, 600, 23):
					boss.t = boss.phase_start + k
					sim.state.x = (60 + k % 240) * SUB
					sim.state.vx = SimConfig.SPEED_X if k % 2 == 0 else -SimConfig.SPEED_X
					var side := 1 if sim.state.vx > 0 else 0
					var at := sim.steps_to_wall(side)
					var safe := 0
					var widest := 0
					var run := 0
					for slot in SimConfig.SLOT_COUNT:
						if boss._safe_span(SimConfig.slot_center_y(slot), at):
							safe |= 1 << slot
							run += 1
							widest = maxi(widest, run)
						else:
							run = 0
					var need := mini(sim.room.def.gap, widest)
					# The usual wall: a gap of 4, elsewhere.
					for gap_start: int in [0, 4, 9]:
						var mask := ALL & ~(0b1111 << gap_start)
						var out: int = boss.adjust_wall(sim, side, mask)
						assert_true(
							_free_ok(out, safe) >= need,
							"%s seed %d phase %d step %d gap %d" % [id, seed_value, p, k, gap_start]
						)
						assert_eq(out & ~mask, 0, "it only clears spikes")
						checked += 1
	assert_true(checked > 100)


func test_a_boss_wall_with_a_safe_gap_is_left_alone() -> void:
	var sim := RoomsTest.sim_in_room("boss_saw", 3)
	var boss := _hazard(sim, "boss_saw")
	# Phase 1: the Saw King's ring doesn't reach the walls (safe_y true).
	boss.phase = 1
	var mask := ALL & ~(0b1111 << 5)
	assert_eq(boss.adjust_wall(sim, 1, mask), mask)


## The planner review's trace (seed 126): wide crates, outer column 0, the
## bird at x 286 flying right, 15 steps before the right bounce. It reaches
## the column 71 steps after the mark: too late to pass under, too early to
## be over the crate. That column is skipped when another one is fair.
func test_wide_crates_skip_a_column_the_bird_reaches_while_it_falls() -> void:
	var sim := RoomsTest.sim_in_room("crates", 1, Seasons.NONE, "wide")
	var cd := _hazard(sim, "crate_drop")
	sim.state.x = 286 * SUB
	sim.state.vx = SimConfig.SPEED_X
	var warn := CrateDrop.WARN_TICKS
	var e: int = cd.entry_steps(sim, 0, 400)
	assert_true(e >= warn and e <= warn + cd.fall_steps(0), "entered at %d" % e)
	assert_false(cd._fair_col(sim, 0, warn))
	var picked: int = cd._free_col(sim, 0, -1, warn)
	assert_true(picked != 0, "another column")
	assert_true(cd._fair_col(sim, picked, warn))


func test_crates_are_marked_fair_whenever_a_fair_column_is_free() -> void:
	var marks := 0
	for variant: String in ["classic", "wide", "pairs"]:
		for seed_value in range(1, 6):
			var sim := RoomsTest.sim_in_room("crates", seed_value, Seasons.NONE, variant)
			var cd := _hazard(sim, "crate_drop")
			var drops: int = cd.drops
			var rng := SimRng.new(seed_value)
			for i in 1500:
				if sim.is_over() or cd.col == -1:
					break
				# Keep the bird alive and in the middle: only x matters here.
				sim.state.y = 320 * SUB
				sim.state.vy = 0
				var before_x := sim.state.x
				var before_vx := sim.state.vx
				sim.step(rng.next_below(9) == 0)
				if cd.drops != drops:
					drops = cd.drops
					# The warning it got (it counts down from the next step).
					var warn: int = cd.warn_left
					marks += 1
					# Judge the mark from where the bird was when it was made.
					var now_x := sim.state.x
					var now_vx := sim.state.vx
					sim.state.x = before_x
					sim.state.vx = before_vx
					var any_fair := false
					for c in cd.cols:
						if cd.heights[c] < cd.max_height and cd._fair_col(sim, c, warn):
							any_fair = true
					if any_fair:
						assert_true(
							cd._fair_col(sim, cd.col, warn),
							"%s seed %d step %d column %d" % [variant, seed_value, i, cd.col]
						)
					sim.state.x = now_x
					sim.state.vx = now_vx
	assert_true(marks > 20, "%d marks" % marks)


func test_squeeze_box_keeps_its_free_runs_in_reach() -> void:
	assert_eq(RoomRules.gap_reach(RoomCatalog.find("squeeze")), RoomRules.GAP_REACH)


## A bird skimming the ceiling or floor line by a wall used to slip past a
## spike in the top or bottom slot.
func test_no_lane_past_the_top_and_bottom_wall_spikes() -> void:
	var sim := GameSim.new(5)
	var r := SimConfig.BIRD_RADIUS
	var right := sim.room.wall_right()
	sim.state.x = right - r
	var cases := [[0, SimConfig.KILL_TOP + r + 2 * SUB], [12, SimConfig.KILL_BOTTOM - r - 2 * SUB]]
	for case: Array in cases:
		var slot: int = case[0]
		sim.state.y = case[1]
		sim.state.right_spikes = 1 << slot
		assert_true(sim._hits_wall(1, right, -1), "slot %d spiked: no lane" % slot)
		sim.state.right_spikes = ALL & ~(1 << slot)
		assert_false(sim._hits_wall(1, right, -1), "slot %d free: the way is open" % slot)
	# A spike in the slot next to the edge one leaves its free edge slot open.
	sim.state.y = SimConfig.slot_center_y(0)
	sim.state.right_spikes = 1 << 1
	assert_false(sim._hits_wall(1, right, -1))


## Lantern Swing: the wall the bird flies to keeps a run of free heights no
## lantern swings in front of while the bird gets there and turns.
func test_a_lantern_never_parks_in_front_of_the_whole_free_run() -> void:
	var checked := 0
	for variant: String in ["big", "twin", "gusty", "winch"]:
		for seed_value in range(1, 4):
			var sim := RoomsTest.sim_in_room("swing", seed_value, Seasons.NONE, variant)
			var lamp := _hazard(sim, "pendulum")
			for k: int in range(0, 420, 37):
				lamp.t = k
				sim.state.x = (40 + k % 280) * SUB
				sim.state.vx = SimConfig.SPEED_X if k % 2 == 0 else -SimConfig.SPEED_X
				var side := 1 if sim.state.vx > 0 else 0
				var blocked := _lantern_blocked(sim, lamp, side)
				var safe := ALL & ~blocked
				var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
				for gap_start: int in [0, 4, 9]:
					var mask := ALL & ~(0b1111 << gap_start)
					var out: int = lamp.adjust_wall(sim, side, mask)
					assert_true(
						_free_ok(out, safe) >= need, "%s seed %d step %d" % [variant, seed_value, k]
					)
					assert_eq(lamp.t, k, "the lantern's clock is put back")
					checked += 1
	assert_true(checked > 100)


## Heights by wall `side` a lantern comes within 4 px of the bird, played
## forward on the lantern's own clock, from 30 steps before the bird gets
## there to 12 after.
static func _lantern_blocked(sim: GameSim, lamp: Hazard, side: int) -> int:
	var at := sim.steps_to_wall(side)
	var r := SimConfig.BIRD_RADIUS
	var edge := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var into := -1 if side == 1 else 1
	var keep: int = lamp.t
	var out := 0
	for d in range(-30, 13, 3):
		lamp.t = keep + at + d
		lamp.step(sim)
		var bx := edge + into * absi(d) * SimConfig.SPEED_X
		var reach: int = lamp.radius + r + 4 * SUB
		for slot in SimConfig.SLOT_COUNT:
			var sy := SimConfig.slot_center_y(slot)
			var hit := _dist2(bx - lamp.x, sy - lamp.y) < reach * reach
			if lamp.has_twin():
				hit = hit or _dist2(bx - lamp.x2, sy - lamp.y2) < reach * reach
			if hit:
				out |= 1 << slot
	lamp.t = keep
	lamp.step(sim)
	return out


static func _dist2(dx: int, dy: int) -> int:
	return dx * dx + dy * dy


## Beam Gates: the wall the bird flies to keeps a run of free heights no live
## beam crosses while the bird gets there and turns.
func test_beams_never_cut_the_whole_free_run() -> void:
	var checked := 0
	for seed_value in range(1, 6):
		var sim := RoomsTest.sim_in_room("beams", seed_value)
		var beam := _hazard(sim, "beam")
		for k: int in range(0, 540, 29):
			beam.t = k
			sim.state.x = (40 + k % 280) * SUB
			sim.state.vx = SimConfig.SPEED_X if k % 2 == 0 else -SimConfig.SPEED_X
			var side := 1 if sim.state.vx > 0 else 0
			var at := sim.steps_to_wall(side)
			var blocked := 0
			for d in range(-6, 31, 6):
				beam.t = k + at + d
				for i in beam.rows.size():
					if beam.state(i) == beam.State.ON:
						for slot in SimConfig.SLOT_COUNT:
							var dy := absi(SimConfig.slot_center_y(slot) - beam.rows[i])
							if dy < beam.HALF_H + SimConfig.BIRD_RADIUS + 4 * SUB:
								blocked |= 1 << slot
			beam.t = k
			var safe := ALL & ~blocked
			var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
			for gap_start: int in [0, 4, 9]:
				var mask := ALL & ~(0b1111 << gap_start)
				var out: int = beam.adjust_wall(sim, side, mask)
				assert_true(_free_ok(out, safe) >= need, "seed %d step %d" % [seed_value, k])
				checked += 1
	assert_true(checked > 50)


## Piston Press: no wall spike shares a ram's row on its own wall (it would
## poke out above or below the ram).
func test_no_wall_spike_in_a_piston_row() -> void:
	const Piston := preload("res://sim/hazards/piston.gd")
	var reach := Piston.HALF_H + SimConfig.SPIKE_HALF_BASE
	var bounces := 0
	for variant: String in ["generated"]:
		for seed_value in range(1, 7):
			var sim := RoomsTest.sim_in_room("piston", seed_value, Seasons.NONE, variant)
			for i in 40:
				# Hazards run on, then the bird bounces as GameSim does.
				for _k in 37 + i % 23:
					sim.room.step(sim)
				var side := 0 if sim.state.vx > 0 else 1
				sim.state.vx = -sim.state.vx
				sim._bounce_score()
				sim._new_wall(side)
				bounces += 1
				for h in sim.room.hazards:
					if h.kind != "piston":
						continue
					var mask: int = sim.state.left_spikes if h.side == 0 else sim.state.right_spikes
					for slot in SimConfig.SLOT_COUNT:
						if RoomRules.has_slot(mask, slot):
							assert_true(
								absi(SimConfig.slot_center_y(slot) - h.y) >= reach,
								"%s seed %d step %d slot %d" % [variant, seed_value, i, slot]
							)
	assert_true(bounces > 20, "%d bounces" % bounces)


## Updraft gust: a wall drawn while the gust blows on the bird's way keeps a
## whole free run from GUST_UP_REACH above to GUST_DOWN_REACH below the bottom
## of the last wall's free run, and no higher than GUST_TOP; with the gust off
## on the way, the wall is left alone.
func test_a_gust_keeps_the_free_run_where_a_lifted_bird_gets() -> void:
	var sim := RoomsTest.sim_in_room("updraft", 4, Seasons.NONE, "gust")
	var air := _hazard(sim, "updraft")
	var blown := 0
	for k: int in range(0, Updraft.GUST_PERIOD, 7):
		air.t = k
		sim.state.x = SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X
		var low := 300 * SUB
		air.last_low = low
		var ok := 0
		for slot in SimConfig.SLOT_COUNT:
			var y := SimConfig.slot_center_y(slot)
			var hi: int = maxi(Updraft.GUST_TOP, low - Updraft.GUST_UP_REACH)
			if y >= hi and y <= low + Updraft.GUST_DOWN_REACH:
				ok |= 1 << slot
		# The usual wall: its gap low down, out of the lifted bird's reach.
		var mask := ALL & ~(0b1111 << 9)
		var out: int = air.adjust_wall(sim, 1, mask)
		if air._gust_on_way(sim, 1):
			blown += 1
			assert_true(_free_ok(out, ok) >= sim.room.def.gap, "step %d" % k)
		else:
			assert_eq(out, mask, "step %d: no gust on the way" % k)
	assert_true(blown > 3)


## The Crusher's jaw keeps last cycle's lane until TELL and then slides to the
## new one: the wall the bird flies to is judged by where the jaw really is.
func test_the_crusher_jaw_is_judged_where_it_is() -> void:
	const Crusher := preload("res://sim/hazards/boss_crusher.gd")
	var sim := RoomsTest.sim_in_room("boss_crusher", 2)
	var boss := _hazard(sim, "boss_crusher")
	boss.phase = 2
	boss.jaw = true
	boss.phase_start = 0
	boss._k = 3
	boss.lane_from = 337 * SUB
	boss.lane_to = 403 * SUB
	boss.press_y = Crusher.PRESS_REST
	boss.plate_y = Crusher.PLATE_REST
	boss.t = 3 * Crusher.CYCLE + 10
	# Before TELL: the old lane (centre 337) is the jaw, not the shown one (403).
	assert_true(boss.safe_y(300 * SUB, 0), "in the old lane")
	assert_false(boss.safe_y(470 * SUB, 0), "only in the new lane: the plate is still there")
	# 10 steps into the slide: the press is 30 px lower, nowhere near the new lane's top yet.
	var lt: int = Crusher.TELL + 10
	assert_true(boss.safe_y(300 * SUB, lt - 10), "the press slides, it doesn't jump")
	assert_false(boss.safe_y(250 * SUB, lt - 10), "but it did move down")


## The Watcher's gaze dart flies from the wall the bird heads to: its mark
## covers a 1 s reaction and the hop out of its lane, and a dart is across
## before the next mark even at tier 3.
func test_the_gaze_dart_mark_covers_a_reaction() -> void:
	const Watcher := preload("res://sim/hazards/boss_watcher.gd")
	assert_true(Watcher.GAZE_TELL >= SimConfig.ARRIVAL_BLIND + 15)
	var across: int = (SimConfig.WORLD_W + Watcher.DART_LEN) / Watcher.DART_SPEED
	assert_true(Watcher.GAZE_TELL + across <= Watcher.GAZE_FAST)
	assert_true(Watcher.GAZE_AT + Watcher.GAZE_TELL < Watcher.CYCLE)


## Crate Drop: the bird's later passes count too (back from the wall), not
## only its first one through a column.
func test_crates_skip_a_column_the_bird_comes_back_into_while_it_falls() -> void:
	var sim := RoomsTest.sim_in_room("crates", 1, Seasons.NONE, "wide")
	var cd := _hazard(sim, "crate_drop")
	# The planner review's gifts/wide entry 11: x 254 flying left; column 1 is
	# crossed before the crate falls, then met again 81 steps on, from the wall.
	sim.state.x = 254 * SUB
	sim.state.vx = -SimConfig.SPEED_X
	var warn := CrateDrop.WARN_TICKS
	assert_true(cd.entry_steps(sim, 1, 400) < warn, "first pass before the fall")
	var again: int = cd.entry_steps(sim, 1, 400, warn)
	assert_true(again <= warn + cd.fall_steps(1), "back in at %d" % again)
	assert_false(cd._fair_col(sim, 1, warn))


## Stalactite Run: after a bounce the column the bird meets first keeps its
## gap (it is about 20 steps from the wall); only the far one moves.
func test_the_near_stalactite_keeps_its_gap_after_a_bounce() -> void:
	for variant: String in ["classic", "floor", "ceiling-only"]:
		for seed_value in range(1, 6):
			var sim := RoomsTest.sim_in_room("stalac", seed_value, Seasons.NONE, variant)
			var cols: Array[Hazard] = []
			for h in sim.room.hazards:
				if h.kind == "stalactite":
					cols.append(h)
			for n in 6:
				for _k in 50:
					sim.room.step(sim)
				var side := 0 if sim.state.vx > 0 else 1
				sim.state.vx = -sim.state.vx
				var near: Hazard = cols[0]
				for h in cols:
					if (h.x < near.x) == (sim.state.vx > 0):
						near = h
				var keep: int = near.target_y
				sim._bounce_score()
				sim._new_wall(side)
				assert_eq(near.target_y, keep, "%s seed %d bounce %d" % [variant, seed_value, n])


## Updraft chimney (always on): every wall the bird flies to across it keeps a
## free run where the lifted bird gets (the same window as a gust's).
func test_a_chimney_keeps_the_free_run_where_a_lifted_bird_gets() -> void:
	var sim := RoomsTest.sim_in_room("updraft", 2, Seasons.NONE, "chimney")
	var air := _hazard(sim, "updraft")
	for low: int in [200 * SUB, 320 * SUB, 480 * SUB]:
		air.last_low = low
		sim.state.x = SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X
		var ok := 0
		for slot in SimConfig.SLOT_COUNT:
			var y := SimConfig.slot_center_y(slot)
			var hi: int = maxi(Updraft.GUST_TOP, low - Updraft.GUST_UP_REACH)
			if y >= hi and y <= low + Updraft.GUST_DOWN_REACH:
				ok |= 1 << slot
		var need := mini(sim.room.def.gap, RoomRules.longest_gap(ALL & ~ok))
		assert_true(air._gust_on_way(sim, 1), "the chimney lifts on the way")
		var out: int = air.adjust_wall(sim, 1, ALL & ~(0b1111 << 9))
		assert_true(_free_ok(out, ok) >= need, "low %d" % (low / SUB))


## Crate pairs out of a portal: no crate falls on a bird that holds its height
## and comes back from the far wall (the fall lasts until the crate lands), so
## the room needs no full ARRIVAL_BLIND wait.
func test_crate_pairs_need_no_long_wait_out_of_a_portal() -> void:
	var sim := RoomsTest.sim_in_room("crates", 1, Seasons.NONE, "pairs")
	var cd := _hazard(sim, "crate_drop")
	sim.state.x = SimConfig.BIRD_RADIUS
	sim.state.vx = SimConfig.SPEED_X
	var warn := CrateDrop.START_DELAY + CrateDrop.WARN_TICKS
	for c in cd.cols:
		if cd._fair_col(sim, c, warn):
			var back: int = cd.entry_steps(sim, c, 400, warn)
			assert_true(back > warn + cd.fall_steps(c), "column %d: back at %d" % [c, back])


## Updraft drift: the band's clock puts it on the bird's way, so the wall
## keeps a free run where the lifted bird gets (as for the other rising bands).
func test_a_drifting_band_on_the_way_lifts_the_bird() -> void:
	var sim := RoomsTest.sim_in_room("updraft", 3, Seasons.NONE, "drift")
	var air := _hazard(sim, "updraft")
	var crossed := 0
	for k: int in range(0, 440, 11):
		air.t = k
		sim.state.x = SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X
		# Flying across the whole room, the bird meets the band wherever it drifts.
		if air._gust_on_way(sim, 1):
			crossed += 1
	assert_eq(crossed, 40, "a full crossing always meets the drifting band")


## Heavy Bramble: the wall the bird flies to keeps a free run above the
## highest the ball gets while the bird crosses (it can fly over the ball).
func test_heavy_bramble_keeps_a_way_over_the_ball() -> void:
	const Heavy := preload("res://sim/hazards/heavy_bouncer.gd")
	for seed_value in range(1, 6):
		var sim := RoomsTest.sim_in_room("bramble", seed_value, Seasons.NONE, "heavy")
		var ball := _hazard(sim, "bouncer")
		assert_true(ball is Heavy, "the heavy ball")
		sim.state.x = SimConfig.BIRD_RADIUS
		sim.state.vx = SimConfig.SPEED_X
		var keep: Array[int] = ball.path_save()
		var peak: int = ball.y
		for k in sim.steps_to_wall(1):
			ball.path_step(sim)
			peak = mini(peak, ball.y)
		ball.path_restore(keep)
		var clear: int = peak - ball.radius - SimConfig.BIRD_RADIUS - Heavy.ESCORT_MARGIN
		var ok := 0
		for slot in SimConfig.SLOT_COUNT:
			if SimConfig.slot_center_y(slot) < clear:
				ok |= 1 << slot
		var need := mini(sim.room.def.gap, RoomRules.longest_gap(ALL & ~ok))
		# A wall open only low down, in the ball's band.
		var out: int = ball.adjust_wall(sim, 1, ALL & ~(0b11111 << 8))
		assert_true(_free_ok(out, ok) >= need, "seed %d" % seed_value)
		assert_eq(ball.path_save(), keep, "the ball is put back")
