extends SceneTree
## The reaction benchmark: for every room, many portal arrivals (heights, sides,
## scores) played by a slow player. For SimConfig.ARRIVAL_BLIND ticks it only
## holds its height (it hasn't read the room yet), then PlannerBot plays on for
## AFTER ticks. Prints each room's deaths against an instant reaction, and
## whether it meets ArrivalBench.MAX_EXTRA_PCT.
##   godot --headless --path . -s res://tools/arrival_bench.gd -- [count] [room | first] [rooms]
## (`room`: a room id; `first`: the first room's index)

const AFTER := 120


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 60
	var first := 0
	var rooms := RoomCatalog.all().size()
	if args.size() > 1:
		# A room id, or the first room's index.
		first = int(args[1]) if args[1].is_valid_int() else RoomCatalog.index_of(args[1])
		rooms = 1 if not args[1].is_valid_int() else rooms
	if args.size() > 2:
		rooms = int(args[2])
	var last := mini(first + rooms, RoomCatalog.all().size())
	for index in range(first, last):
		var r := ArrivalBench.room(index, count, SimConfig.ARRIVAL_BLIND, AFTER)
		var ok: bool = r.extra * 100 <= ArrivalBench.MAX_EXTRA_PCT * count
		print(
			(
				"%-10s extra %3d  (slow %2d, instant %2d of %d)  %s  %s"
				% [r.id, r.extra, r.dead, r.dead_now, count, "ok" if ok else "FAIL", r.causes]
			)
		)
	quit(0)
