extends SceneTree
## Portal arrivals into one room, fast: many arrivals at different heights and
## directions; the bot holds its height for <delay> ticks, then PlannerBot
## plays. Prints deaths and what killed the bird.
##   godot --headless --path . -s res://tools/arrival_room.gd -- <room id> [delay] [count]

const AFTER := 120


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "gates"
	var delay := int(args[1]) if args.size() > 1 else 45
	var count := int(args[2]) if args.size() > 2 else 60
	var index := RoomCatalog.index_of(id)
	var def := RoomCatalog.all()[index]
	var dead := 0
	var causes := {}
	for i in count:
		var sim := GameSim.new(9000 + i * 37)
		sim.step(true)
		sim.state.score = maxi(def.from_score, 10) + (i % 3) * 10
		sim.state.y = (130 + (i * 53) % 380) * SimConfig.SUB
		# As out of a real portal: the hidden arrival check picks the layout.
		for k in sim._arrival_retries(i % 2, index):
			sim._rng.next_u32()
		sim._arrive_in(i % 2, index)
		var y0 := sim.state.y
		var bot := PlannerBot.new(i + 1)
		var n := 0
		while n < delay + AFTER and not sim.is_over():
			var tap: bool
			if n < delay:
				var g := sim.room.def.gravity_sign
				tap = (sim.state.y - y0) * g > 0 and sim.state.vy * g >= 0
			else:
				tap = bot.decide(sim)
			sim.step(tap)
			n += 1
		if sim.is_over():
			dead += 1
			var why: String = SimState.DeathCause.keys()[sim.state.death_cause]
			var key := "%s@%s" % [why, "blind" if n <= delay else "play"]
			causes[key] = int(causes.get(key, 0)) + 1
	print("%s delay %d: %d/%d died  %s" % [id, delay, dead, count, causes])
	quit(0)
