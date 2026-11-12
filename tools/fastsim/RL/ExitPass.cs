using System.Collections.Concurrent;

namespace FastSim.Rl;

/// `rl review exitpass --room stalac`: is a room's exit placed where a bird can
/// take it on the first pass? Tool only. For each variant, seed and random
/// surviving line (as the `reach` check plays them), from the step the exit's
/// ghost shows: can SurvivalSearch go through the exit on the bird's first
/// arrival at the exit's wall (no extra crossing)? Also with the two spare
/// crossings the `reach` check allows.
public static class ExitPass
{
    public static int run(Dictionary<string, string> opts, int seeds, int threads)
    {
        string id = opts.GetValueOrDefault("room", "stalac");
        int lines = int.Parse(opts.GetValueOrDefault("lines", "3"));
        var def = RoomCatalog.all()[(int)RoomCatalog.index_of(id)];
        var variants = def.variants.Count == 0 ? new List<string> { "classic" } : def.variants.Select(v => v.id).ToList();
        var shown = new ConcurrentDictionary<string, int>();
        var first = new ConcurrentDictionary<string, int>();
        var spare = new ConcurrentDictionary<string, int>();
        var bad = new ConcurrentBag<string>();
        var jobs = variants.SelectMany(v => Enumerable.Range(0, seeds).SelectMany(s => Enumerable.Range(0, lines).Select(l => (v, s, l)))).ToList();
        Parallel.ForEach(jobs, new ParallelOptions { MaxDegreeOfParallelism = threads }, job =>
        {
            var (v, s, l) = job;
            long seed = 1000 + s * 61;
            var sim = Checks.Setups.practice(id, seed, v);
            var rnd = new Random((int)seed * 7 + l);
            long done = 0;
            while (!sim.state.exit_preview && !sim.is_over() && done < 1500)
            {
                var ss = new SurvivalSearch { pick = rnd };
                if (!ss.run(sim, 360)) return;
                int n = Math.Min(120, ss.best_inputs.Length);
                for (int i = 0; i < n && !sim.state.exit_preview; i++)
                {
                    sim.step(ss.best_inputs[i] == 1);
                    done++;
                }
            }
            if (!sim.state.exit_preview) return;
            shown.AddOrUpdate(v, 1, (_, x) => x + 1);
            long room = sim.state.room_index;
            long crossing = (sim.room.wall_right() - sim.room.wall_left()) / SimConfig.SPEED_X;
            long to_exit = sim.steps_to_exit(sim.state.exit_side);
            var a = new SurvivalSearch();
            a.run(sim.clone_deep(), to_exit + SimConfig.PORTAL_HOLD + 10);
            bool ok1 = a.best != null && a.best.state.room_index != room;
            var b = new SurvivalSearch();
            b.run(sim.clone_deep(), to_exit + 2 * crossing + SimConfig.PORTAL_HOLD + 10);
            bool ok2 = b.best != null && b.best.state.room_index != room;
            if (ok1) first.AddOrUpdate(v, 1, (_, x) => x + 1);
            if (ok2) spare.AddOrUpdate(v, 1, (_, x) => x + 1);
            if (!ok1) bad.Add($"{v} seed {seed} line {l}: exit {sim.state.exit_a_y / SimConfig.SUB} px, bird {sim.state.y / SimConfig.SUB} px{(ok2 ? "" : " (not even with 2 spare crossings)")}");
        });
        Console.WriteLine($"exit on the first pass from the ghost, room {id}, {seeds} seeds x {lines} lines, gameplay {SimConfig.GAMEPLAY_VERSION}");
        Console.WriteLine("variant\tghosts\tfirst pass\twith 2 spare");
        foreach (var v in variants)
            Console.WriteLine($"{v}\t{shown.GetValueOrDefault(v)}\t{first.GetValueOrDefault(v)}\t{spare.GetValueOrDefault(v)}");
        foreach (var x in bad.OrderBy(x => x)) Console.WriteLine("miss\t" + x);
        return 0;
    }
}
