extends SceneTree
## Room odds per score band from the real picker (RoomCatalog.pick_next, its
## deck and RoomPacing): plays the room picks of many runs (a pick at every
## POINTS_PER_ROOM points, a boss at every BOSS_EVERY, arrival heights spread
## over the exit range) and prints one TSV line per band and room:
## `ODDS band_from band_to room group count share_pct`, and one per score and
## room: `PICK score room count`.
##   godot --headless --path . -s res://tools/room_odds.gd -- [runs] [season] [max_score]
## Season: a Seasons number (-1 = none, the default). Reads the sim only.

const BANDS := [[10, 19], [20, 49], [50, 99], [100, 199], [200, 299], [300, 499], [500, 999]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := args[0].to_int() if args.size() > 0 else 2000
	var season := args[1].to_int() if args.size() > 1 else Seasons.NONE
	var max_score := args[2].to_int() if args.size() > 2 else 990
	var counts := []
	var by_score := {}
	for b in BANDS:
		counts.append({})
	var low := SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE
	var high := SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	for run in runs:
		var rng := SimRng.new(1000 + run)
		var heights := SimRng.new(500000 + run)
		var state := SimState.new()
		var current := RoomCatalog.first_index()
		for score in range(SimConfig.POINTS_PER_ROOM, max_score + 1, SimConfig.POINTS_PER_ROOM):
			if score % SimConfig.BOSS_EVERY == 0:
				current = RoomCatalog.bosses()[0]
				continue
			state.score = score
			state.anchor_y = low + heights.next_below(high - low)
			current = RoomCatalog.pick_next(rng, state, current, season)
			var key := score * 1000 + current
			by_score[key] = by_score.get(key, 0) + 1
			for b in BANDS.size():
				if score >= BANDS[b][0] and score <= BANDS[b][1]:
					var c: Dictionary = counts[b]
					c[current] = c.get(current, 0) + 1
	for b in BANDS.size():
		var c: Dictionary = counts[b]
		var total := 0
		for k: int in c:
			total += c[k]
		for k: int in c:
			var def: RoomDef = RoomCatalog.all()[k]
			print(
				(
					"ODDS\t%d\t%d\t%s\t%s\t%d\t%.2f"
					% [BANDS[b][0], BANDS[b][1], def.id, def.group, c[k], 100.0 * c[k] / total]
				)
			)
	for key: int in by_score:
		print(
			"PICK	%d	%s	%d" % [key / 1000, RoomCatalog.all()[key % 1000].id, by_score[key]]
		)
	quit(0)
