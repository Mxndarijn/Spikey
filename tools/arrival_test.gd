extends SceneTree
## Portal arrivals with a slow player. Plays real runs with PlannerBot; at every
## arrival in a new room it tries the same moment again for each reaction delay:
## for that many ticks the bot only holds its height (it hasn't read the room
## yet), then PlannerBot plays on. Reports how often each delay dies soon after.
##   godot --headless --path . -s res://tools/arrival_test.gd -- <out.json> [seeds] [first]

const DELAYS := [0, 30, 45, 60]
## Ticks after the delay (and the portal wait) that count as "died on arrival".
const AFTER := 120
const RUN_TICKS := 7000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://arrivals.json"
	var seeds := int(args[1]) if args.size() > 1 else 2
	var first := int(args[2]) if args.size() > 2 else 0
	var arrivals := []
	for s in seeds:
		var seed_value := 7000 + (first + s) * 131
		var sim := GameSim.new(seed_value)
		var bot := PlannerBot.new(seed_value)
		while not sim.is_over() and sim.state.tick < RUN_TICKS:
			sim.step(bot.decide(sim))
			if GameSim.Event.ROOM_CHANGE in sim.events:
				arrivals.append(_trial_all(sim, seed_value))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arrivals": arrivals}, "  "))
	f.close()
	print("arrivals: %d -> %s" % [arrivals.size(), out])
	quit(0)


func _trial_all(sim: GameSim, seed_value: int) -> Dictionary:
	var row := {"seed": seed_value, "room": RoomCatalog.all()[sim.state.room_kind].id}
	for d: int in DELAYS:
		row[str(d)] = _trial(sim, d, seed_value + sim.state.tick, false)
		row["r" + str(d)] = _trial(sim, d, seed_value + sim.state.tick, true)
	return row


## Ticks survived after arrival, minus the cap: 0 means it lived to the end.
## `rhythm`: while not reacting, tap every 24 ticks instead of holding height.
func _trial(sim: GameSim, delay: int, bot_seed: int, rhythm: bool) -> int:
	var cap := delay + AFTER + sim.state.arrival_hold
	var c := SimClone.copy(sim)
	var bot := PlannerBot.new(bot_seed)
	var y0 := c.state.y
	var n := 0
	while n < cap and not c.is_over():
		var tap: bool
		if n < delay:
			var g := c.room.gravity
			tap = (c.state.y - y0) * g > 0 and c.state.vy * g >= 0
			if rhythm:
				tap = n % 24 == 12
		else:
			tap = bot.decide(c)
		c.step(tap)
		n += 1
	return n - cap
