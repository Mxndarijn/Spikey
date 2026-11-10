extends SceneTree
## Times the playtest bots, so speedups can be measured.
##   godot --headless --path . -s res://tools/bot_bench.gd
## Prints microseconds per sim copy and per step, PlannerBot decisions per
## second, and how long a SurvivalSearch run takes. Also prints checksums of
## what the bots produced, so a speedup can be checked to change nothing.

const COPIES := 2000
const STEPS := 20000
const DECISIONS := 300
const SEARCH_TICKS := 1500


func _initialize() -> void:
	# Copy and step costs, averaged over every room kind (practice runs a few
	# ticks in, so the hazards are set up).
	var rng := SimRng.new(7)
	var rooms := RoomCatalog.all()
	var copy_total := 0
	var step_total := 0
	var steps_done := 0
	for index in rooms.size():
		var def: RoomDef = rooms[index]
		var sim := GameSim.new(1077, def.season, index)
		for i in 40:
			sim.step(PlannerBot.aim(sim, rng))
		if sim.is_over():
			sim = GameSim.new(1077, def.season, index)
		var t0 := Time.get_ticks_usec()
		for i in COPIES / rooms.size() + 1:
			SimClone.copy(sim)
		copy_total += Time.get_ticks_usec() - t0
		var stepper := SimClone.copy(sim)
		var n := 0
		var per_room := STEPS / rooms.size() + 1
		while n < per_room:
			if stepper.is_over():
				stepper = SimClone.copy(sim)
			t0 = Time.get_ticks_usec()
			stepper.step(PlannerBot.aim(stepper, rng))
			step_total += Time.get_ticks_usec() - t0
			n += 1
		steps_done += n
	var copy_us := float(copy_total) / ((COPIES / rooms.size() + 1) * rooms.size())
	var step_us := float(step_total) / steps_done
	var t0 := 0

	var play := GameSim.new(5000)
	var bot := PlannerBot.new(5000)
	t0 = Time.get_ticks_usec()
	var made := 0
	while made < DECISIONS and not play.is_over():
		play.step(bot.decide(play))
		made += 1
	var decide_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxi(made, 1)

	var search := SurvivalSearch.new()
	var start := GameSim.new(5000)
	t0 = Time.get_ticks_usec()
	var ok := search.run(start, SEARCH_TICKS)
	var search_s := float(Time.get_ticks_usec() - t0) / 1000000.0
	var taps := 0
	for b in search.best_inputs:
		taps = (taps * 31 + b + 1) & 0x7FFFFFFF

	print("copy      %8.1f us" % copy_us)
	print("step      %8.1f us" % step_us)
	print("decide    %8.2f ms  (%.0f decisions/s)" % [decide_ms, 1000.0 / decide_ms])
	print(
		(
			"search    %8.2f s   (%d ticks, ok %s, width %d)"
			% [search_s, search.ticks_survived, ok, search.peak_width]
		)
	)
	print(
		(
			"planner checksum %d  tick %d score %d"
			% [play.state.checksum(), play.state.tick, play.state.score]
		)
	)
	print("search checksum  %d  inputs %d" % [taps, search.best_inputs.size()])
	quit(0)
